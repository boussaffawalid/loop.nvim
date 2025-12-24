local strtools = require('loop.tools.strtools')
local class = require('loop.tools.class')

-- namespace for error highlights
local _error_hl_ns = vim.api.nvim_create_namespace("LoopPluginOutputCompHl")

---@class loop.comp.output.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.comp.output.PendingLine
---@field line string
---@field highlights loop.comp.output.Highlight[]|nil

---@class loop.comp.OutputLines
---@field new fun(self: loop.comp.OutputLines) : loop.comp.OutputLines
---@field _linked_buf loop.BufferController|nil
---@field _pending_lines loop.comp.output.PendingLine[]
local OutputLines = class()

function OutputLines:init()
    self._pending_lines = {}
end

---@param buf_ctrl loop.BufferController
function OutputLines:link_to_buffer(buf_ctrl)
    self._linked_buf = buf_ctrl
    self._linked_buf.set_renderer({
        render = function(bufnr, user_data)
            return self:_render(bufnr)
        end
    })
    buf_ctrl:request_refresh()
end

---@param line string
---@param highlights loop.comp.output.Highlight[]|nil
function OutputLines:add_line(line, highlights)
    ---@type loop.comp.output.PendingLine
    local pending = {
        line = line,
        highlights = highlights
    }
    table.insert(self._pending_lines, pending)
    if self._linked_buf then
        self._linked_buf.request_refresh()
    end
end

---@param buf number
function OutputLines:_render(buf)
    if #self._pending_lines == 0 then
        return false
    end

    local pending_lines = self._pending_lines
    self._pending_lines = {}

    -- Insert lines into the buffer
    local lines_to_insert = {}
    for _, pending in ipairs(pending_lines) do
        table.insert(lines_to_insert, pending.line)
    end

    local line_count = vim.api.nvim_buf_line_count(buf)

    vim.bo[buf].modifiable = true
    if line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, lines_to_insert)
    else
        vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, lines_to_insert)
    end
    vim.bo[buf].modifiable = false


    -- Apply highlights using extmarks
    for i, pending in ipairs(pending_lines) do
        if pending.highlights then
            local buf_line = line_count + i - 1
            for _, hl in ipairs(pending.highlights) do
                local start_col = hl.start_col or 0
                local end_col = hl.end_col or #pending.line
                vim.api.nvim_buf_set_extmark(buf, _error_hl_ns, buf_line, start_col, {
                    end_col = end_col,
                    hl_group = hl.group,
                })
            end
        end
    end

    return true
end

return OutputLines
