local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')
local uitools = require('loop.tools.uitools')
local BaseBuffer = require('loop.buf.BaseBuffer')

---@class loop.comp.ReplBuffer:loop.comp.BaseBuffer
---@field new fun(self: loop.comp.ReplBuffer, type:string, name:string):loop.comp.ReplBuffer
local ReplBuffer = class(BaseBuffer)

local COLORS = {
    RESET = "\27[0m",
    BOLD  = "\27[1m",
    GREEN = "\27[32m",
    BLUE  = "\27[34m",
    RED   = "\27[31m",
    CYAN  = "\27[36m",
}

function ReplBuffer:init(type, name)
    BaseBuffer.init(self, type, name)
    self._chan = nil
    self._current_line = ""
    self._cursor_pos = 1
    self._history = {}
    self._history_idx = 0
    self._prompt = COLORS.BOLD .. COLORS.GREEN .. "> " .. COLORS.RESET

    ---@type {request_counter:number,current_request:number}
    self._completion = {
        request_counter = 0, -- Tracks the unique ID of the latest request
        current_request = -1,
    }

    ---@type fun(input:string)?
    self._input_handler = nil

    ---@type loop.ReplCompletionHandler?
    self._completion_handler = nil
end

---@return loop.ReplController
function ReplBuffer:make_controller()
    ---@type loop.ReplController
    return {
        set_input_handler = function(handler)
            self._input_handler = handler
        end,
        set_completion_handler = function(handler)
            self._completion_handler = handler
        end,
        add_output = function(text)
            self:send_line(text)
        end
    }
end

---@param line string
function ReplBuffer:on_input(line)
    line = vim.fn.trim(line, "", 1) -- trim left
    if line == "" then return end
    if self._input_handler then
        self._input_handler(line)
    else
        self:send_line(COLORS.CYAN .. "No command handler" .. COLORS.RESET)
    end
end

function ReplBuffer:on_complete(line, callback)
    if self._completion_handler then
        -- Increment tracking
        self._completion.request_counter = self._completion.request_counter + 1
        local request_id = self._completion.request_counter
        self._completion.current_request = request_id

        self._completion_handler(line, function(suggestions)
            local current_left = self._current_line:sub(1, self._cursor_pos - 1)
            if request_id == self._completion.request_counter and line == current_left then
                callback(suggestions or {})
            end
        end)
    else
        callback({})
    end
end

function ReplBuffer:send_line(text)
    if self._chan then
        -- 1. \r: Move to start of line
        -- 2. \27[K: Clear everything on the prompt line (the old "> ")
        -- 3. Print the actual text + newline
        -- 4. Re-print the prompt at the very end
        local formatted = "\r\27[K" .. text .. "\r\n" .. self._prompt .. self._current_line
        vim.api.nvim_chan_send(self._chan, formatted)
    end
end

---Refreshes the current input line in the terminal
function ReplBuffer:_redraw_line()
    -- 1. Move to start of line (\r) and clear it (\27[K)
    -- 2. Print prompt + full current line
    -- 3. Move cursor back to the correct position
    --    The column is: (length of prompt without ANSI codes) + self._cursor_pos

    -- Strip ANSI codes from prompt to calculate length
    local clean_prompt = self._prompt:gsub("\27%[[%d;]*m", "")
    local col = #clean_prompt + self._cursor_pos

    -- \27[%dG moves the cursor to the absolute horizontal column
    local out = "\r\27[K" .. self._prompt .. self._current_line .. "\27[" .. col .. "G"
    vim.api.nvim_chan_send(self._chan, out)
end

function ReplBuffer:_setup_buf()
    BaseBuffer._setup_buf(self)
    local buf = self:get_buf()
    assert(buf and buf > 0)
    vim.keymap.set('t', '<Esc>', function() vim.cmd('stopinsert') end, { buffer = buf })
    -- FORCE TAB to be handled directly
    -- Without this, Neovim might intercept Tab for its own purposes.
    vim.keymap.set('t', '<Tab>', function()
        self:_handle_raw_input("\t")
    end, { buffer = buf, silent = true })
    self._chan = vim.api.nvim_open_term(buf, {
        on_input = function(_, _, _, data)
            self:_handle_raw_input(data)
        end
    })
    self:_redraw_line()
end

function ReplBuffer:_handle_raw_input(data)
    -- 0. Ctrl+C (Interrupt)
    if data == "\3" then
        self._completion.current_request = -1
        vim.api.nvim_chan_send(self._chan, "^C\r\n")
        self._current_line = ""
        self._cursor_pos = 1
        self:_redraw_line()
        return
    end

    -- 1. Enter (Submission)
    if data == "\r" or data == "\n" then
        local line = self._current_line
        vim.api.nvim_chan_send(self._chan, "\r\n")

        self._current_line = ""
        self._cursor_pos = 1 -- Reset cursor to start
        self._history_idx = 0

        if line ~= "" and self._history[#self._history] ~= line then
            table.insert(self._history, line)
        end

        self:on_input(line)
        vim.api.nvim_chan_send(self._chan, "\r\27[K" .. self._prompt)
        return
    end

    -- 2. Tab (Complete)
    if data == "\t" then
        local is_at_end = self._cursor_pos > #self._current_line
        local char_after = self._current_line:sub(self._cursor_pos, self._cursor_pos)

        -- Logic:
        -- 1. Always allow if at the end of the line.
        -- 2. If in the middle, only allow if there is a space immediately after the cursor.
        local should_complete = is_at_end or (char_after == " ")

        if not should_complete then
            return
        end

        local line_to_cursor = self._current_line:sub(1, self._cursor_pos - 1)
        local line_after_cursor = self._current_line:sub(self._cursor_pos)

        self:on_complete(line_to_cursor, function(targets)
            self:_apply_completion(line_to_cursor, line_after_cursor, targets)
        end)
        return
    end

    -- 3. Ctrl+p or Arrow up (History)
    if data == "\16" or data == "\27[A" then
        if #self._history > 0 and (self._history_idx == 0 or self._history_idx > 1) then
            self._completion.current_request = -1 -- DISCARD pending completion
            self._history_idx = self._history_idx == 0 and #self._history or self._history_idx - 1
            self._current_line = self._history[self._history_idx]
            self._cursor_pos = #self._current_line + 1
            self:_redraw_line()
        end
        return
    end

    -- 4. Ctrl+n or Arrow down (History)
    if data == "\14" or data == "\27[B" then
        self._completion.current_request = -1 -- DISCARD pending completion
        if self._history_idx > 0 then
            if self._history_idx < #self._history then
                self._history_idx = self._history_idx + 1
                self._current_line = self._history[self._history_idx]
            else
                self._history_idx = 0
                self._current_line = ""
            end
            self._cursor_pos = #self._current_line + 1
            self:_redraw_line()
        end
        return
    end

    if data == "\27[D" then -- Left
        if self._cursor_pos > 1 then
            self._cursor_pos = self._cursor_pos - 1
            self:_redraw_line()
        end
        return
    end

    if data == "\27[C" then -- Right
        if self._cursor_pos <= #self._current_line then
            self._cursor_pos = self._cursor_pos + 1
            self:_redraw_line()
        end
        return
    end

    -- 4. Backspace (Deletion at Cursor)
    if data == "\b" or data == string.char(127) then
        if self._cursor_pos > 1 then
            local left = self._current_line:sub(1, self._cursor_pos - 2)
            local right = self._current_line:sub(self._cursor_pos)
            self._current_line = left .. right
            self._cursor_pos = self._cursor_pos - 1
            self._completion.current_request = -1
            self:_redraw_line()
        end
        return
    end

    -- 5. Regular Text Input (Insertion at Cursor)
    -- We ignore any remaining escape sequences starting with \27
    if not data:find("^\27") then
        local left = self._current_line:sub(1, self._cursor_pos - 1)
        local right = self._current_line:sub(self._cursor_pos)
        self._current_line = left .. data .. right
        self._cursor_pos = self._cursor_pos + #data
        self._completion.current_request = -1
        self:_redraw_line()
        return
    end
end

---Handles the result of an asynchronous completion request
---@param line_to_cursor string Text before/at cursor
---@param line_after_cursor string Text after cursor
---@param targets string[]
function ReplBuffer:_apply_completion(line_to_cursor, line_after_cursor, targets)
    if not targets or #targets == 0 then return end

    -- 1. Single Suggestion
    if #targets == 1 then
        -- Handle both raw string arrays or LLDB target objects
        local suggestion = type(targets[1]) == "table" and targets[1] or targets[1]

        -- Extract the prefix (everything before the word being completed)
        local prefix, fragment = line_to_cursor:match("(.-)([^%s]*)$")

        local is_word_match = suggestion:lower():find("^" .. vim.pesc(fragment:lower()))

        local new_before
        if is_word_match then
            -- Replace the fragment with the suggestion
            new_before = prefix .. suggestion
        elseif suggestion:lower():find("^" .. vim.pesc(line_to_cursor:lower())) then
            -- Suggestion is a full replacement of the left side
            new_before = suggestion
        else
            -- No overlap found, just append to the current word
            new_before = prefix .. fragment .. suggestion
        end

        -- APPLY: Merge the new head with the existing tail
        self._current_line = new_before .. line_after_cursor

        -- MOVE CURSOR: Place it right after the completion
        self._cursor_pos = #new_before + 1

        self:_redraw_line()

        -- 2. Multiple Suggestions: Render Grid
    elseif #targets > 1 then
        local display_items = {}
        for _, t in ipairs(targets) do
            local text = type(t) == "table" and t.text or t
            table.insert(display_items, text)
        end

        local win_width = uitools.get_window_text_width()
        local grid = strtools.format_grid(display_items, win_width)

        -- Print grid and redraw the line (cursor stays where it was)
        vim.api.nvim_chan_send(self._chan, "\r\n" .. grid .. "\r\n")
        self:_redraw_line()
    end
end

return ReplBuffer
