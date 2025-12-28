local class = require("loop.tools.class") -- your utility

---@class loop.TrackerRef
---@field cancel fun()

---@generic T  -- T = user-defined callbacks type
---@class loop.tools.Trackers<T>
---@field private _next_id integer
---@field private _items table<integer, any>
---@field new fun(self: loop.tools.Trackers) : loop.tools.Trackers
local Trackers = class()

function Trackers:init()
    self._next_id = 0
    self._items = {}
end

---Add a tracker and return its unique id
---@generic T
---@param callbacks T
---@return loop.TrackerRef
function Trackers:add_tracker(callbacks)
    local id = self._next_id + 1
    self._next_id = id
    self._items[id] = callbacks
    ---@type loop.TrackerRef
    return {
        cancel = function()
            self._items[id] = nil
        end
    }
end

---Invoke a callback on each tracker if that callback exists
---@param async boolean
---@param callback_name string
---@param ... any
function Trackers:_invoke(async, callback_name, ...)
    local n = select("#", ...)
    local args = {}
    -- Manually copy each argument including nils
    for i = 1, n do
        args[i] = select(i, ...)
    end
    if async then
        vim.schedule(function()
            for _, tracker in pairs(self._items) do
                local fn = tracker[callback_name]
                if fn then
                    fn(unpack(args, 1, n))
                end
            end
        end)
    else
        for _, tracker in pairs(self._items) do
            local fn = tracker[callback_name]
            if fn then
                fn(unpack(args, 1, n))
            end
        end
    end
end

---Invoke a callback on each tracker if that callback exists
---@param callback_name string
---@param ... any
function Trackers:invoke(callback_name, ...)
    self:_invoke(true, callback_name, ...)
end

---Invoke a callback on each tracker if that callback exists
---@param callback_name string
---@param ... any
function Trackers:invoke_sync(callback_name, ...)
    self:_invoke(false, callback_name, ...)
end

return Trackers
