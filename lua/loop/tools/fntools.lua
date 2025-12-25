local M = {}

-- Returns a version of fn that can only be called once
function M.called_once(fn)
    local called = false
    return function(...)
        if called then
            return
        end
        called = true
        return fn(...)
    end
end

return M