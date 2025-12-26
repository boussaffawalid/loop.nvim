local class = require('loop.tools.class')
local Tree = require("loop.tools.Tree")
local Trackers = require("loop.tools.Trackers")

---@class loop.comp.ItemTree.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@alias loop.comp.ItemTree.ChildrenCallback fun(items:loop.comp.ItemTree.Item[])

---@class loop.comp.ItemTree.Item
---@field id any
---@field data any
---@field parent_id any
---@field children_callback nil|fun(cb:loop.comp.ItemTree.ChildrenCallback,retry:boolean|nil))
---@field expanded boolean|nil

---@class loop.comp.ItemTree.ItemData
---@field userdata any
---@field children_callback nil|fun(cb:fun(items:loop.comp.ItemTree.Item[],retry:boolean|nil))
---@field expanded boolean|nil
---@field reload_children boolean|nil
---@field children_loading boolean|nil
---@field is_loading boolean|nil

---@class loop.comp.ItemTree.Tracker
---@field on_selection? fun(id:any,data:any)
---@field on_open? fun(id:any,data:any)
---@field on_toggle? fun(id:any,data:any,expanded:boolean)

---@class loop.comp.ItemTree.InitArgs
---@field formatter fun(id:any,data:any,out_highlights:loop.comp.ItemTree.Highlight[]):string
---@field expand_char string?
---@field collapse_char string?
---@field indent_string string?
---@field loading_text string?
---@field render_delay_ms number|nil

---@class loop.comp.ItemTree
---@field new fun(self: loop.comp.ItemTree, args:loop.comp.ItemTree.InitArgs): loop.comp.ItemTree
---@field _linked_buf loop.BufferController|nil
local ItemTree = class()

local _ns_id = vim.api.nvim_create_namespace('LoopPluginItemTreeComp')

---@param item loop.comp.ItemTree.Item
---@return loop.comp.ItemTree.ItemData
local function _item_to_itemdata(item)
    ---@type loop.comp.ItemTree.ItemData
    return {
        userdata = item.data,
        children_callback = item.children_callback,
        expanded = item.expanded,
        reload_children = true,
    }
end

---@param tree loop.tools.Tree
---@param async_update fun()
---@return loop.tools.Tree.FlatNode[]
---@return boolean have loading nodes
local function _refresh_tree(tree, async_update)
    ---@type loop.tools.Tree.FlatNode[]
    local flat = {}
    local have_loading_nodes = false
    -- Get all nodes in depth-first order
    ---@type loop.tools.Tree.FlatNode[]
    local nodes = tree:flatten(function(id, data)
        if not data.expanded then
            return "exclude_children"
        end
        return nil
    end)

    for _, flat_node in ipairs(nodes) do
        table.insert(flat, flat_node)
        ---@type loop.comp.ItemTree.ItemData
        local item = flat_node.data
        -- Only show children if node is expanded
        if item.expanded then
            local item_id = flat_node.id
            -- Lazy loading
            if item.children_callback and item.reload_children ~= false and not item.children_loading then
                item.children_loading = true
                have_loading_nodes = true

                vim.schedule(function()
                    -- Trigger async load
                    item.children_callback(function(loaded_children, retry)
                        -- process only if parent still exists
                        if tree:get_item(item_id) then
                            ---@type loop.tools.Tree.Item[]
                            local treeitems = {}
                            for _, child in ipairs(loaded_children or {}) do
                                ---@type loop.tools.Tree.Item
                                local basetreeitem = { id = child.id, data = _item_to_itemdata(child) }
                                table.insert(treeitems, basetreeitem)
                            end
                            tree:set_children(item_id, treeitems)
                            item.children_loading = false
                            item.reload_children = false
                            if retry == true then
                                item.reload_children = true
                                item.expanded = false
                            end
                            async_update()
                        end
                    end)
                end)
            end
            if item.children_loading then
                ---@type loop.comp.ItemTree.ItemData
                local loading_item = {
                    id = {}, -- unique id
                    is_loading = true
                }
                ---@type loop.tools.Tree.FlatNode
                table.insert(flat, {
                    id = loading_item.id,
                    data = loading_item,
                    depth = flat_node.depth + 1,
                })
            end
        end
    end
    return flat, have_loading_nodes
end

---@param args loop.comp.ItemTree.InitArgs
function ItemTree:init(args)
    assert(args.formatter, "formatter is required")

    self._formatter = args.formatter
    self._trackers = Trackers:new()

    self._expand_char = args.expand_char or "▸"
    self._collapse_char = args.collapse_char or "▾"
    self._indent_string = args.indent_string or "  "
    self._loading_text = args.loading_text or "Loading..."
    self._render_delay_ms = args.render_delay_ms or 150

    self._tree = Tree:new()

    ---@type loop.tools.Tree.FlatNode[]
    self._flat = {}
end

---------------------------------------------------------
-- TRACKERS
---------------------------------------------------------
---@param cb loop.comp.ItemTree.Tracker
---@return number
function ItemTree:add_tracker(cb) return self._trackers:add_tracker(cb) end

---@param id number
---@return boolean
function ItemTree:remove_tracker(id) return self._trackers:remove_tracker(id) end

--- linked comp ---
---@param buf_ctrl loop.BufferController
function ItemTree:link_to_buffer(buf_ctrl)
    local cur_item_data = function()
        local cursor = buf_ctrl:get_cursor()
        if not cursor then return nil end
        local row = cursor[1]
        ---@type loop.tools.Tree.FlatNode
        local node = self._flat[row]
        if not node then return nil, nil end
        return node.id, node.data
    end

    local function on_open()
        local id, itemdata = cur_item_data()
        if not id or not itemdata then return end
        self._trackers:invoke("on_open", id, itemdata.userdata)
    end

    local function on_toggle()
        local id, itemdata = cur_item_data()
        if not id or not itemdata then return end
        local have_children = self._tree:have_children(id)
        if have_children or itemdata.children_callback then
            self:toggle_expand(id)
        end
    end

    self._linked_buf = buf_ctrl
    self._linked_buf.set_renderer({
        render = function(bufnr)
            return self:_on_render_request(bufnr)
        end
    })

    self._linked_buf.add_keymap('<CR>', { callback = on_toggle, desc = "Select or expand/collapse" })
    self._linked_buf.add_keymap('go', { callback = on_open, desc = "Open details" })
    self._linked_buf.add_keymap('<2-LeftMouse>', { callback = on_toggle, desc = "Select or expand/collapse" })
    self._linked_buf.add_keymap('zo', { callback = on_toggle, desc = "Expand node" })
    self._linked_buf.add_keymap('zc', { callback = on_toggle, desc = "Collapse node" })
    self._linked_buf.add_keymap('za', { callback = on_toggle, desc = "Toggle expand/collapse" })

    buf_ctrl:request_refresh()
end

---------------------------------------------------------
-- ITEM MANAGEMENT
---------------------------------------------------------

---@param comp loop.BufferController
---@return loop.comp.ItemTree.Item|nil
function ItemTree:get_cur_item(comp)
    local cursor = comp:get_cursor()
    if not cursor then return nil end
    local row = cursor[1]

    ---@type loop.tools.Tree.FlatNode
    local node = self._flat[row]
    if not node then return nil end

    ---@type number,loop.comp.ItemTree.ItemData
    local id, nodedata = node.id, node.data

    ---@type loop.comp.ItemTree.Item
    return { id = id, data = nodedata.userdata }
end

---@param id any
---@return loop.comp.ItemTree.Item|nil
function ItemTree:get_item(id)
    ---@type loop.comp.ItemTree.ItemData?
    local itemdata = self:_get_item(id)
    if not itemdata then return nil end
    ---@type loop.comp.ItemTree.Item
    return { id = id, data = itemdata.userdata }
end

function ItemTree:clear_items()
    self._tree = Tree:new()
    self:_request_render()
end

---@param items loop.comp.ItemTree.Item[]
function ItemTree:upsert_items(items)
    for _, item in ipairs(items) do
        self._tree:upsert_item(item.parent_id, item.id, _item_to_itemdata(item))
    end
    self:_request_render()
end

---@param item loop.comp.ItemTree.Item
function ItemTree:upsert_item(item)
    self._tree:upsert_item(item.parent_id or nil, item.id, _item_to_itemdata(item))
    self:_request_render()
end

---@param ids any[]
function ItemTree:remove_items(ids)
    for _, id in ipairs(ids) do
        self._tree:remove_item(id)
    end
    self:_request_render()
    return true
end

function ItemTree:remove_item(id)
    self._tree:remove_item(id)
    self:_request_render()
    return true
end

function ItemTree:_request_render()
    if self._linked_buf then
        self._linked_buf.request_refresh()
    end
end

---@param buf number
---@return boolean
function ItemTree:_on_render_request(buf)
    local flat, have_loading_nodes = _refresh_tree(self._tree, function()
        vim.schedule(function() self:_request_render() end)
    end)

    -- Handle patience delay
    if have_loading_nodes and not self._no_delay_next_render then
        vim.defer_fn(function()
            self._no_delay_next_render = true
            self:_request_render()
        end, self._render_delay_ms or 150)
        return false
    end
    self._no_delay_next_render = false

    local buffer_lines = {}
    local extmarks = {}
    local new_flat_nodes = {}

    for _, flatnode in ipairs(flat) do
        local item_id = flatnode.id
        local item = flatnode.data

        -- Generate Prefix
        local icon = ""
        if item_id and (self._tree:have_children(item_id) or item.children_callback) then
            icon = item.expanded and self._collapse_char or self._expand_char
        end
        local prefix = string.rep(self._indent_string, flatnode.depth or 0)
        if icon ~= "" then
            prefix = prefix .. icon .. " "
        else
            prefix = prefix .. string.rep(" ", vim.fn.strdisplaywidth(self._expand_char)) .. " "
        end

        -- Get Content
        local raw_hls = {}
        local raw_text = ""
        if item.is_loading then
            raw_text = self._loading_text
            raw_hls = { { group = "Comment" } }
        else
            raw_text = (item_id and self._formatter(item_id, item.userdata, raw_hls) or "")
        end

        -- Process lines and multi-line highlights
        local node_lines, mappings, all_node_hls = self:_process_node_lines(
            flatnode, prefix, raw_text, raw_hls
        )

        for i, line in ipairs(node_lines) do
            table.insert(buffer_lines, line)
            table.insert(new_flat_nodes, mappings[i])

            local current_row = #buffer_lines - 1
            local hls_for_this_line = all_node_hls[i]

            for _, hl in ipairs(hls_for_this_line) do
                table.insert(extmarks, {
                    row = current_row,
                    col_start = hl.start_col,
                    col_end = hl.end_col,
                    group = hl.group,
                })
            end
        end
    end

    -- Update state
    self._flat = new_flat_nodes

    -- Draw to buffer
    vim.api.nvim_buf_clear_namespace(buf, _ns_id, 0, -1)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_lines)
    vim.bo[buf].modifiable = false

    -- Apply extmarks
    for _, mark in ipairs(extmarks) do
        vim.api.nvim_buf_set_extmark(buf, _ns_id, mark.row, mark.col_start, {
            end_col = mark.col_end,
            hl_group = mark.group,
        })
    end

    return true
end

---@param node_data table The flatnode
---@param prefix string Indent + Expand/Collapse char
---@param text string Raw text from formatter
---@param highlights loop.comp.ItemTree.Highlight[]
---@return string[] lines, any[] flat_mappings, loop.comp.ItemTree.Highlight[][] line_highlights
function ItemTree:_process_node_lines(node_data, prefix, text, highlights)
    local lines = {}
    local mappings = {}
    ---@type loop.comp.ItemTree.Highlight[][]
    local line_highlights = {} -- This will be a list of lists

    local node_lines = vim.split(text, "\n", { trimempty = false })
    local prefix_width = vim.fn.strdisplaywidth(prefix)
    local empty_prefix = string.rep(" ", prefix_width)

    -- Track the character offset for each line to map highlights
    local current_offset = 0
    for i, line_content in ipairs(node_lines) do
        local current_prefix = (i == 1) and prefix or empty_prefix
        table.insert(lines, current_prefix .. line_content)
        table.insert(mappings, node_data)

        ---@type loop.comp.ItemTree.Highlight[]
        local current_line_hls = {}
        local line_start = current_offset
        local line_end = current_offset + #line_content

        for _, hl in ipairs(highlights) do
            local hl_start = hl.start_col or 0
            local hl_end = hl.end_col or #text

            -- Check if the highlight intersects with this specific line
            local intersect_start = math.max(line_start, hl_start)
            local intersect_end = math.min(line_end, hl_end)

            if intersect_start < intersect_end then
                -- Translate the global offset to a line-local offset
                -- and add the prefix length
                table.insert(current_line_hls, {
                    group = hl.group,
                    start_col = #current_prefix + (intersect_start - line_start),
                    end_col = #current_prefix + (intersect_end - line_start),
                })
            end
        end

        table.insert(line_highlights, current_line_hls)
        -- +1 to account for the \n we split on
        current_offset = line_end + 1
    end

    return lines, mappings, line_highlights
end

---------------------------------------------------------
-- EXPAND / COLLAPSE
---------------------------------------------------------
function ItemTree:toggle_expand(id)
    local item = self:_get_item(id)
    if item then
        item.expanded = not item.expanded
        self:_request_render()
        self._trackers:invoke("on_toggle", id, item.userdata, item.expanded)
    end
end

function ItemTree:expand(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = true
        self:_request_render()
        self._trackers:invoke("on_toggle", id, item.userdata, true)
    end
end

function ItemTree:collapse(id)
    local item = self._tree:get_item(id)
    if item then
        item.expanded = false
        self:_request_render()
        self._trackers:invoke("on_toggle", id, item.userdata, false)
    end
end

---@return loop.comp.ItemTree.ItemData|nil
function ItemTree:_get_item(id)
    return self._tree:get_item(id)
end

---@return loop.comp.ItemTree.Item[]
function ItemTree:get_items()
    local items = {}
    for _, treeitem in ipairs(self._tree:get_items()) do
        ---@type loop.comp.ItemTree.ItemData
        local data = treeitem.data
        ---@type loop.comp.ItemTree.Item
        local item = {
            id = treeitem.id,
            data = data.userdata,
            expanded = data.expanded,
        }
        table.insert(items, item)
    end
    return items
end

---@param item_id any
---@return loop.comp.ItemTree.Item[]
function ItemTree:get_item_and_children(item_id)
    ---@type loop.tools.Tree.FlatNode[]
    local nodes = self._tree:flatten(function(id, data)
        if id == item_id then
            return "keep"
        else
            return "exclude"
        end
    end)

    local items = {}
    for _, node in ipairs(nodes) do
        ---@type loop.comp.ItemTree.ItemData
        local itemdata = node.data
        ---@type loop.comp.ItemTree.Item
        local curitem = {
            id = node.id,
            data = itemdata.userdata,
            expanded = itemdata.expanded,
        }
        table.insert(items, curitem)
    end
    return items
end

---------------------------------------------------------
-- Refresh
---------------------------------------------------------
function ItemTree:refresh_content()
    self:_request_render()
end

return ItemTree
