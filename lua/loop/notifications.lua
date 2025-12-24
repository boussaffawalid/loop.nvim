local M = {}

---@param text string|string[]
---@param level integer|nil One of the values from |vim.log.levels
function M.notify(text, level)
    if level and level < vim.log.levels.INFO then        
        M.log(text)
        return
    end
    if type(text) == 'table' then
        local lines = {}
        for idx, str in ipairs(text) do
            table.insert(lines, str)
        end
        if #lines > 0 then
            lines[1] = "loop.nvim: " .. lines[1]
            vim.notify(table.concat(lines, '\n'), level)
        end
    else
        vim.notify("loop.nvim: " .. text, level)
    end
end

---@param text string|string[]
function M.log(text)
    
end

return M
