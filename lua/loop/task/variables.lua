local M = {}

---@type table<string, table<string, string>>
-- Maps config_dir to variables table (variable name -> raw value)
local _variables = {}

---@param config_dir string
---@param variables table<string, string>
function M.set_variables(config_dir, variables)
    _variables[config_dir] = variables or {}
end

---@param config_dir string
---@param name string
---@return string|nil
function M.get_variable(config_dir, name)
    local vars = _variables[config_dir]
    if not vars then
        return nil
    end
    return vars[name]
end

---@param config_dir string
function M.clear_variables(config_dir)
    _variables[config_dir] = nil
end

return M

