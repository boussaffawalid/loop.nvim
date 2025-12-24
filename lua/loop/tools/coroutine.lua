local M = {}

function M.run_coroutine(fn)
    local co = coroutine.create(fn)
    local alive = true

    local function step(...)
        if not alive then
            return
        end

        local ok, yielded = coroutine.resume(co, ...)
        if not ok then
            alive = false
            error(yielded)
        end

        if coroutine.status(co) == "dead" then
            alive = false
            return
        end

        yielded(function(...)
            if not alive then
                return
            end
            step(...)
        end)
    end

    step()
end

return M
