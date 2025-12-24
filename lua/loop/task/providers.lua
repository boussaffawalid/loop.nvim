-- IMPORTANT: keep this module light for lazy loading

---@type table<string,string>  -- name -> module
local _registry = {
    composite = "loop.coretasks.composite.provider",
    build     = "loop.coretasks.build.provider",
    run       = "loop.coretasks.run.provider",
    vimcmd    = "loop.coretasks.vimcmd.provider",
}

---@type string[]  -- keeps registration order
local _order = { "composite", "build", "run", "vimcmd" }

local M = {}

---@return boolean
function M.register(name, module)
    if _registry[name] then
        return false
    end
    _registry[name] = module
    table.insert(_order, name)
    return true
end

---@return boolean
function M.is_valid_provider(name)
    return _registry[name] ~= nil
end

---@return string[]
function M.names()
    -- return keys in registration order
    return vim.list_extend({}, _order) -- shallow copy
end

---@param name string
---@return string|nil
function M.get_provider_modname(name)
    return _registry[name]
end

return M
