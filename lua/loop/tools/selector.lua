local config = require('loop.config')

---@class loop.SelectorItem
---@field label string
---@field data any
---@alias loop.SelectorCallback fun(data: any|nil)

local M = {}

-- One single namespace for the whole module
local _ns_prompt = vim.api.nvim_create_namespace("LoopPluginItemSelectPrompt")

--- Use Telescope to show the selector
---@param prompt string The prompt title
---@param items loop.SelectorItem[] List of items
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
local function _telescope_select(prompt, items, formatter, callback)
    local pickers = require("telescope.pickers")
    local previewers = require("telescope.previewers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local state = require("telescope.actions.state")
    local previewer
    if formatter then
        previewer = previewers.new_buffer_previewer({
            title = "Details",
            --- @param self table
            --- @param entry table
            --- @param status table
            define_preview = function(self, entry, status)
                -- Format and split data into lines
                local formatted, filetype = formatter(entry.value.data)
                local lines = vim.split(formatted, "\n")
                -- Set lines in the preview buffer
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                -- Set filetype for syntax highlighting
                vim.bo[self.state.bufnr].filetype = filetype or ""
                -- Enable line wrapping in this buffer's window
                local win = self.state.winid
                assert(win and win > 0)
                vim.wo[win].wrap = true
                vim.wo[win].linebreak = true
                vim.wo[win].foldmethod = "indent"
                vim.wo[win].spell = false
            end,
        })
    end
    pickers.new({}, {
        prompt_title = prompt,
        finder = finders.new_table({
            results = items,
            --- @param entry loop.SelectorItem
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.label,
                    ordinal = entry.label,
                }
            end,
        }),
        previewer = previewer,
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            -- Replace default select action
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = state.get_selected_entry()
                local item = selection and selection.value or nil
                if item and callback then
                    callback(item.data)
                end
            end)
            -- Optional: allow <C-c> to cancel
            map("i", "<C-c>", function()
                actions.close(prompt_bufnr)
                if callback then callback(nil) end
            end)
            return true
        end,
    }):find()
end

-- Use Snacks.nvim picker as fallback
---@param prompt string
---@param items loop.SelectorItem[]
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
local function _snacks_select(prompt, items, formatter, callback)
    local snacks = require("snacks")

    -- Map items for Snacks.nvim
    local snack_items = {}
    for _, item in ipairs(items) do
        table.insert(snack_items, {
            text = item.label,
            value = item,
            file = ""
        })
    end

    local previewer
    if formatter then
        previewer = function(ctx)
            local jsonstr, filetype = formatter(ctx.item.value.data)
            vim.bo[ctx.buf].modifiable = true
            vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, vim.split(jsonstr, "\n"))
            vim.bo[ctx.buf].modifiable = false
            vim.bo[ctx.buf].filetype = filetype or ""
            return true
        end
    end

    -- Show the picker
    snacks.picker({
        title = prompt,
        items = snack_items,
        format = "text",
        preview = previewer,
        confirm = function(picker, item)
            vim.schedule(function()
                picker:close()
                if callback and item and item.value then
                    callback(item.value.data)
                end
            end)
        end
    })
end

local function fuzzy_filter(items, query)
    if query == "" then return vim.fn.copy(items) end
    local q = query:lower()
    local res = {}
    for _, item in ipairs(items) do
        if item.label:lower():find(q, 1, true) then table.insert(res, item) end
    end
    return res
end

local function _update_prompt(prompt_prefix, query, pbuf, pwin)
    local full_text = prompt_prefix .. query
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { full_text })

    -- Clear previous highlights/extmarks in this namespace
    pcall(vim.api.nvim_buf_clear_namespace, pbuf, _ns_prompt, 0, -1)

    -- Apply the new highlight via extmark (non-deprecated)
    vim.api.nvim_buf_set_extmark(pbuf, _ns_prompt, 0, 0, {
        end_col = #prompt_prefix,
        hl_group = "Title",
    })

    -- Force cursor position *after* the text is set
    vim.schedule(function()
        pcall(vim.api.nvim_win_set_cursor, pwin, { 1, #full_text })
    end)
end

local function _update_list(filtered, cur, lbuf, lwin)
    local lines = {}
    for i, item in ipairs(filtered) do
        lines[i] = (i == cur and "> " or "  ") .. tostring(item.label)
    end
    vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, lines)
    pcall(vim.api.nvim_win_set_cursor, lwin, { cur, 0 })
end

local function _update_preview(has_preview, formatter, filtered, cur, vbuf)
    if not has_preview then return end
    local item = filtered[cur]
    if not item then
        vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, { "" })
        return
    end
    local ok, txt, filetype = pcall(formatter, item.data)
    vim.bo[vbuf].filetype = filetype or ""
    vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, vim.split(ok and txt or "<error>", "\n"))
end

local function _redraw(items, query, filtered, cur)
    filtered = fuzzy_filter(items, query)
    cur = #filtered > 0 and math.min(cur, #filtered) or 1
    return filtered, cur
end

local function _close(callback, callback_called, res, windows, buffers)
    if not callback_called then
        callback_called = true
        vim.schedule(function()
            callback(res)
        end)
    end
    vim.cmd("stopinsert")
    for _, w in ipairs(windows) do
        if w and vim.api.nvim_win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
        end
    end
    for _, b in ipairs(buffers) do
        if b and vim.api.nvim_buf_is_valid(b) then
            vim.api.nvim_buf_delete(b, { force = true })
        end
    end
    return callback_called
end

local function _move(filtered, cur, d)
    if #filtered == 0 then return cur end
    cur = (cur - 1 + d) % #filtered + 1
    return cur
end

---@param prompt string The prompt/title to display
---@param items loop.SelectorItem[] List of items with label and data table
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
function _builtin_select(prompt, items, formatter, callback)
    if #items == 0 then return callback(nil) end
    local callback_called = false
    local has_preview = type(formatter) == "function"
    
    local width = math.floor(vim.o.columns * (has_preview and 0.66 or 0.33))
    local height = math.floor(vim.o.lines * 0.66)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local list_w = has_preview and math.ceil(width * 0.5) - 2 or width
    local preview_col_offset = list_w + 2
    local prev_w = has_preview and (width - preview_col_offset) or 0

    local query = ""
    local filtered = vim.fn.copy(items)
    local cur = 1
    
    local pbuf = vim.api.nvim_create_buf(false, true)
    local lbuf = vim.api.nvim_create_buf(false, true)
    local vbuf = has_preview and vim.api.nvim_create_buf(false, true) or nil

    vim.bo[pbuf].buftype = 'nofile'
    vim.bo[pbuf].bufhidden = 'delete'
    vim.bo[lbuf].buftype = 'nofile'
    vim.bo[lbuf].bufhidden = 'delete'
    if vbuf then
        vim.bo[vbuf].buftype = 'nofile'
        vim.bo[vbuf].bufhidden = 'delete'
    end

    -- Define a transparent border highlight if it doesn't exist
    -- This sets the background to "none" while keeping the foreground color
    vim.cmd([[highlight default LoopTransparentBorder guibg=NONE]])

    local win_config = {
        relative = "editor",
        style = "minimal",
        border = "rounded",
    }

    local pwin = vim.api.nvim_open_win(pbuf, true, vim.tbl_extend("force", win_config, {
        width = width, height = 1, row = row - 3, col = col,
    }))

    local lwin = vim.api.nvim_open_win(lbuf, false, vim.tbl_extend("force", win_config, {
        width = list_w, height = height, row = row, col = col,
    }))

    local vwin = vbuf and vim.api.nvim_open_win(vbuf, false, vim.tbl_extend("force", win_config, {
        width = prev_w, height = height, row = row, col = col + preview_col_offset, 
    })) or nil

    -- FIX: Set FloatBorder to our transparent group
    -- 'NormalFloat:Normal' ensures the window background matches your editor
    -- 'FloatBorder:LoopTransparentBorder' makes the border background transparent
    local winhl = "NormalFloat:Normal,FloatBorder:LoopTransparentBorder,CursorLine:Visual"
    
    vim.wo[pwin].winhighlight = winhl
    vim.wo[lwin].winhighlight = winhl
    if vwin then 
        vim.wo[vwin].winhighlight = winhl 
        vim.wo[vwin].wrap = true
    end

    local prompt_prefix = prompt .. " > "

    local function redraw()
        filtered, cur = _redraw(items, query, filtered, cur)
        _update_prompt(prompt_prefix, query, pbuf, pwin)
        _update_list(filtered, cur, lbuf, lwin)
        _update_preview(has_preview, formatter, filtered, cur, vbuf)
    end

    local function close(res)
        callback_called = _close(callback, callback_called, res, { pwin, lwin, vwin }, { pbuf, lbuf, vbuf })
    end

    local function move(d)
        cur = _move(filtered, cur, d)
        redraw()
    end

    redraw()

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = pbuf,
        once = true,
        callback = function() close(nil) end,
    })

    local opts = { buffer = pbuf, nowait = true, silent = true }
    vim.keymap.set("i", "<CR>", function() close(filtered[cur] and filtered[cur].data or nil) end, opts)
    vim.keymap.set("i", "<Esc>", function() close(nil) end, opts)
    vim.keymap.set("i", "<C-c>", function() close(nil) end, opts)
    vim.keymap.set("i", "<C-n>", function() move(1) end, opts)
    vim.keymap.set("i", "<C-p>", function() move(-1) end, opts)
    vim.keymap.set("i", "<Down>", function() move(1) end, opts)
    vim.keymap.set("i", "<Up>", function() move(-1) end, opts)
    vim.keymap.set("i", "<BS>", function()
        if #query > 0 then query = query:sub(1, -2); redraw() end
    end, opts)

    for i = 32, 126 do
        local c = string.char(i)
        vim.keymap.set("i", c, function() query = query .. c; redraw() end, opts)
    end
    vim.cmd("startinsert")
end

---@param prompt string The prompt/title to display
---@param items loop.SelectorItem[] List of items with label and data table
---@param previewer (fun(data:any):string,string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
function M.select(prompt, items, previewer, callback)
    local type = config.current.selector
    if not type or type == "" or type == "builtin" then
        return _builtin_select(prompt, items, previewer, callback)
    elseif type == "telescope" then
        _telescope_select(prompt, items, previewer, callback)
    elseif type == "snacks" then
        _snacks_select(prompt, items, previewer, callback)
    end
end

return M
