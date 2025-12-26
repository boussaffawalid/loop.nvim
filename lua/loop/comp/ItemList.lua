local class = require('loop.tools.class')
local Trackers = require("loop.tools.Trackers")

---@class loop.comp.ItemList.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.comp.ItemList.Item
---@field id any
---@field data any

---@class loop.comp.ItemList.Tracker
---@field on_selection? fun(id:any,data:any)
---@field on_open? fun(id:any,data:any)

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemListComp')

---@class loop.comp.ItemList.InitArgs
---@field formatter fun(item:loop.comp.ItemList.Item,out_highlights:loop.comp.ItemList.Highlight[]):string
---@field show_current_prefix boolean|nil            # NEW: whether to show ">" prefix on current item
---@field current_prefix string|nil                  # NEW: custom prefix, defaults to "> "
---@field render_delay_ms number|nil

---@class loop.comp.ItemList
---@field new fun(self: loop.comp.ItemList, args:loop.comp.ItemList.InitArgs): loop.comp.ItemList
---@field _args loop.comp.ItemList.InitArgs
---@field _items loop.comp.ItemList.Item[]
---@field _index table<any,number>
---@field _select_handler fun(item:loop.comp.ItemList.Item|nil)
---@field _trackers loop.tools.Trackers<loop.comp.ItemList.Tracker>
---@field _current_item loop.comp.ItemList.Item|nil   # NEW: currently active item
---@field _current_prefix string                            # NEW: resolved prefix
---@field _linked_buf loop.CompBufferController|nil
local ItemList = class()

---@param args loop.comp.ItemList.InitArgs
function ItemList:init(args)
    assert(args.formatter)
    self._args = args
    self._items = {}
    self._index = {}

    self._trackers = Trackers:new()

    -- NEW: current item tracking
    self._current_item = nil
    if args.show_current_prefix then
        self._current_prefix = args.current_prefix or "> "
        self._noncurrent_prefix = (" "):rep(#self._current_prefix)
    end
end

---@param buf_ctrl loop.CompBufferController
function ItemList:link_to_buffer(buf_ctrl)
    local get_cur_item = function()
        local cursor = buf_ctrl:get_cursor()
        if not cursor then return nil end
        local row = cursor[1]
        return self._items[row]
    end

    self._linked_buf = buf_ctrl
    self._linked_buf.set_renderer({
        render = function(bufnr)
            return self:render(bufnr)
        end
    })

    local select_handler = function()
        local item = get_cur_item()
        if item then
            self:set_current_item(item) -- will trigger prefix update if enabled
            self._trackers:invoke("on_selection", item.id, item.data)
        end
    end

    local open_handler = function()
        local item = get_cur_item()
        if item then
            self._trackers:invoke("on_open", item.id, item.data)
        end
    end

    self._linked_buf.add_keymap('<CR>', { callback = select_handler, desc = "Select item" })
    self._linked_buf.add_keymap('<2-LeftMouse>', { callback = select_handler, desc = "Select item" })
    self._linked_buf.add_keymap('go', { callback = open_handler, desc = "Open details" })

    buf_ctrl:request_refresh()
end

-- NEW: Public API to set current item (used by selection, or externally)
---@param item loop.comp.ItemList.Item|nil
function ItemList:set_current_item(item)
    if self._current_item == item then return end
    self._current_item = item
    if self._args.show_current_prefix then
        self:refresh_content() -- rebuild lines with updated prefixes
    end
end

---@param id any
function ItemList:set_current_item_by_id(id)
    self:set_current_item(self:get_item(id))
end

-- NEW: Get current item (cursor fallback if none explicitly set)
---@return loop.comp.ItemList.Item|nil
function ItemList:get_current_item()
    return self._current_item
end

---@param callbacks loop.comp.ItemList.Tracker
---@return number
function ItemList:add_tracker(callbacks) return self._trackers:add_tracker(callbacks) end

---@return boolean
function ItemList:remove_tracker(id) return self._trackers:remove_tracker(id) end

function ItemList:set_items(items)
    self._items = items
    self._index = {}
    for i, item in ipairs(items) do
        assert(not self._index[item.id], "duplicate item id")
        self._index[item.id] = i
    end
    -- Reset current item if it's no longer in the list
    if self._current_item and not self._index[self._current_item.id] then
        self._current_item = nil
    end
    self:_request_render()
end

function ItemList:upsert_item(item)
    assert(item and item.id and item.data)

    local idx = self._index[item.id]
    if idx then
        -- Update existing item
        self._items[idx] = item
    else
        -- Insert new item
        idx = #self._items + 1
        self._items[idx] = item
        self._index[item.id] = idx
    end

    -- If this item is the current one, keep reference stable
    if self._current_item and self._current_item.id == item.id then
        self._current_item = item
    end

    -- Schedule a render (throttled)
    self:_request_render()
end

---@return loop.comp.ItemList.Item[]
function ItemList:get_items()
    return self._items
end

---@param id number
---@return loop.comp.ItemList.Item
function ItemList:get_item(id)
    local idx = self._index[id]
    return idx and self._items[idx] or nil
end

---@param id number
function ItemList:remove_item(id)
    local idx = self._index[id]
    if not idx then return end

    if self._current_item and self._current_item.id == id then
        self._current_item = nil
    end

    table.remove(self._items, idx)
    self._index[id] = nil
    for i = idx, #self._items do
        self._index[self._items[i].id] = i
    end

    self:_request_render()
end

---@param buf number
---@param idx number
---@param highlights loop.comp.ItemList.Highlight[]
function ItemList:_highlight(buf, idx, highlights)
    local item = self._items[idx]
    if #highlights > 0 then
        local line_text = vim.api.nvim_buf_get_lines(buf, idx - 1, idx, false)[1] or ""
        local line_len = #line_text

        -- Adjust for current prefix if present
        local offset = 0
        if self._args.show_current_prefix then
            if self._current_item and self._current_item.id == item.id then
                offset = #self._current_prefix
            else
                offset = #self._noncurrent_prefix
            end
        end

        for _, hl in ipairs(highlights) do
            local start_col = (hl.start_col or 0) + offset
            local end_col = hl.end_col and (hl.end_col + offset) or (line_len)
            end_col = math.min(end_col, line_len)

            start_col = math.max(0, start_col)
            if start_col < end_col then
                vim.api.nvim_buf_set_extmark(buf, _ns_id, idx - 1, start_col, {
                    end_col = end_col,
                    hl_group = hl.group,
                    priority = 200,
                })
            end
        end
    end
end

---@param buf number
---@return boolean
function ItemList:render(buf)
    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)

    ---@type loop.comp.ItemList.Highlight[][]
    local all_highlights = {}
    local lines = {}
    for _, item in ipairs(self._items) do
        local highlights = {}
        local text = self._args.formatter(item, highlights):gsub("\n", " ")
        table.insert(all_highlights, highlights)
        if self._args.show_current_prefix then
            if self._current_item and self._current_item.id == item.id then
                text = self._current_prefix .. text
            else
                text = self._noncurrent_prefix .. text
            end
        end
        lines[#lines + 1] = text
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    assert(#all_highlights == #lines)
    for idx, highlights in ipairs(all_highlights) do
        self:_highlight(buf, idx, highlights)
    end

    return true
end

function ItemList:_request_render()
    if self._linked_buf then
        self._linked_buf.request_refresh()
    end
end

function ItemList:refresh_content()
    self:_request_render()
end

return ItemList
