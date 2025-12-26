local class = require('loop.tools.class')
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
    self._history = {}
    self._history_idx = 0
    self._prompt = COLORS.BOLD .. COLORS.GREEN .. "> " .. COLORS.RESET

    ---@type fun(input:string)?
    self._input_handler = nil
end

---@return loop.ReplController
function ReplBuffer:make_controller()
    ---@type loop.ReplController
    return {
        set_input_handler = function(handler)
            self._input_handler = handler
        end,
        add_output = function(text)
            self:send_line(text)
        end
    }
end

---@param line string
function ReplBuffer:on_input(line)
    if self._input_handler then
        self._input_handler(line)
    else
        self:send_line(COLORS.CYAN .. "No command handler" .. COLORS.RESET)
    end
end

---@param line string
---@return string[]
function ReplBuffer:on_complete(line)
    --TODO: implement tab completion here
    return {}
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
    -- \r: carriage return, \27[K: clear line from cursor right
    vim.api.nvim_chan_send(self._chan, "\r\27[K" .. self._prompt .. self._current_line)
end

function ReplBuffer:_setup_buf()
    BaseBuffer._setup_buf(self)
    local buf = self:get_buf()
    assert(buf and buf > 0)
    vim.keymap.set('t', '<Esc>', function() vim.cmd('stopinsert') end, { buffer = buf })
    self._chan = vim.api.nvim_open_term(buf, {
        on_input = function(_, _, _, data)
            self:_handle_raw_input(data)
        end
    })
    vim.api.nvim_chan_send(self._chan,
        COLORS.GREEN .. "REPL Ready (Arrows for history, Tab for complete)" .. COLORS.RESET .. "\r\n" .. self._prompt)
end

function ReplBuffer:_handle_raw_input(data)
    -- 1. Enter
    if data == "\r" or data == "\n" then
        local line = self._current_line

        -- Move cursor to a fresh line before processing
        vim.api.nvim_chan_send(self._chan, "\r\n")

        self._current_line = ""
        self._history_idx = 0

        if line ~= "" and self._history[#self._history] ~= line then
            table.insert(self._history, line)
        end

        -- IMPORTANT: Do not print the prompt here.
        -- self:on_input() will call send_line(), which now handles prompt printing.
        self:on_input(line)

        -- If on_input didn't produce output (and thus didn't print a prompt),
        -- we ensure a prompt exists for the next command.
        -- We use \r\27[K to avoid double prompts.
        vim.api.nvim_chan_send(self._chan, "\r\27[K" .. self._prompt)

        -- 2. Tab (Complete)
    elseif data == "\t" then
        local suggestions = self:on_complete(self._current_line)
        if #suggestions == 1 then
            self._current_line = suggestions[1]
            self:_redraw_line()
        elseif #suggestions > 1 then
            vim.api.nvim_chan_send(self._chan, "\r\n" .. table.concat(suggestions, "  ") .. "\r\n")
            self:_redraw_line()
        end

        -- 3. Arrow Keys (History)
        -- Up: \27[A, Down: \27[B
    elseif data == "\27[A" then -- Up
        if #self._history > 0 and (self._history_idx == 0 or self._history_idx > 1) then
            if self._history_idx == 0 then
                self._history_idx = #self._history
            else
                self._history_idx = self._history_idx - 1
            end
            self._current_line = self._history[self._history_idx]
            self:_redraw_line()
        end
    elseif data == "\27[B" then -- Down
        if self._history_idx > 0 then
            if self._history_idx < #self._history then
                self._history_idx = self._history_idx + 1
                self._current_line = self._history[self._history_idx]
            else
                self._history_idx = 0
                self._current_line = ""
            end
            self:_redraw_line()
        end

        -- 4. Backspace
    elseif data == "\b" or data == string.char(127) then
        if #self._current_line > 0 then
            self._current_line = self._current_line:sub(1, -2)
            vim.api.nvim_chan_send(self._chan, "\b \b")
        end

        -- 5. Regular Input
    else
        -- Simple check to ignore other escape sequences (like Left/Right arrows for now)
        if not data:find("^\27") then
            self._current_line = self._current_line .. data
            vim.api.nvim_chan_send(self._chan, data)
        end
    end
end

return ReplBuffer
