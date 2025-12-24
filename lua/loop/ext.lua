-- IMPORTANT: keep this module light for lazy loading

local M = {}

local providers = require('loop.task.providers')

---@return boolean
function M.register_task_provider(name, module)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "Invalid extension name: " .. tostring(name))
    assert(module and module:match("^[%w_.-][%w_.-]*$") ~= nil, "Invalid extension module: " .. tostring(module))
    return providers.register(name, module)
end

return M