local class = require("loop.tools.class")

---@alias loop.scheduler.exit_trigger "cycle"|"invalid_node"|"interrupt"|"node"
---@alias loop.scheduler.exit_fn fun(success:boolean,trigger:loop.scheduler.exit_trigger,param:any)
---@alias loop.scheduler.NodeId string
---@alias loop.scheduler.StartNodeFn fun(id: loop.scheduler.NodeId, on_exit: fun(ok:boolean, reason:string|nil)): { terminate:fun() }|nil, string|nil
---@alias loop.scheduler.NodeEvent "start"|"stop"
---@alias loop.scheduler.NodeEventFn fun(id: loop.scheduler.NodeId, event: loop.scheduler.NodeEvent)

---@class loop.scheduler.Node
---@field id loop.scheduler.NodeId
---@field deps loop.scheduler.NodeId[]?
---@field order "sequence"|"parallel"|nil

local Scheduler = class()

--──────────────────────────────────────────────────────────────────────────────
-- Constructor
--──────────────────────────────────────────────────────────────────────────────

function Scheduler:init(nodes, start_node)
    self._nodes = {}
    for _, n in ipairs(nodes) do
        self._nodes[n.id] = n
    end

    self._start_node = start_node

    self._inflight = {} 
    self._running = {}
    self._visiting = {}
    self._done = {}

    self._pending_running = 0
    self._terminated = true
    self._terminating = false
    self._pending_start = nil
    self._run_id = 0
    self._current_node_event = nil
end

--──────────────────────────────────────────────────────────────────────────────
-- Public API
--──────────────────────────────────────────────────────────────────────────────

---@param root loop.scheduler.NodeId
---@param on_node_event loop.scheduler.NodeEventFn
---@param on_exit loop.scheduler.exit_fn
function Scheduler:start(root, on_node_event, on_exit)
    self._pending_start = { root = root, on_node_event = on_node_event, on_exit = on_exit }

    if self._terminating then return end
    if not self._terminated then
        self:terminate()
        return
    end

    self:_start_pending()
end

function Scheduler:terminate()
    if self._terminated or self._terminating then return end
    self._terminating = true
    
    -- Snapshot running nodes to avoid iterator invalidation
    local to_stop = {}
    for id, ctl in pairs(self._running) do
        to_stop[id] = ctl
    end

    for _, ctl in pairs(to_stop) do
        pcall(ctl.terminate)
    end
    
    self:_check_termination_complete()
end

function Scheduler:is_running() return not self._terminated end
function Scheduler:is_terminated() return self._terminated end
function Scheduler:is_terminating() return self._terminating end

--──────────────────────────────────────────────────────────────────────────────
-- Internal: lifecycle
--──────────────────────────────────────────────────────────────────────────────

function Scheduler:_broadcast_event(id, event)
    -- 1. Notify the primary run listener
    if self._current_node_event then
        pcall(self._current_node_event, id, event)
    end

    -- 2. Notify any secondary listeners waiting for this specific node
    local listeners = self._inflight[id]
    if not listeners then return end
    for _, cb in ipairs(listeners) do
        if cb.on_node_event and cb.on_node_event ~= self._current_node_event then
            pcall(cb.on_node_event, id, event)
        end
    end
end

function Scheduler:_check_termination_complete()
    if self._terminated then return end
    if self._pending_running > 0 then return end

    self._terminating = false
    self._terminated = true
    self._running = {}
    self._visiting = {}
    self._done = {}
    self._inflight = {}
    self._current_node_event = nil

    -- Start next queued run if applicable
    vim.schedule(function() self:_start_pending() end)
end

function Scheduler:_start_pending()
    if not self._terminated or self._terminating then return end
    local p = self._pending_start
    if not p then return end
    self._pending_start = nil

    self._run_id = self._run_id + 1
    local my_run = self._run_id

    self._terminated = false
    self._visiting = {}
    self._running = {}
    self._done = {}
    self._inflight = {}
    self._pending_running = 0
    self._current_node_event = p.on_node_event

    self:_run_node(p.root, p.on_node_event, function(ok, trigger, param)
        if my_run ~= self._run_id then return end
        if p.on_exit then pcall(p.on_exit, ok, trigger, param) end
        self:_check_termination_complete()
    end)
end

--──────────────────────────────────────────────────────────────────────────────
-- Internal: graph execution
--──────────────────────────────────────────────────────────────────────────────

---@param id loop.scheduler.NodeId
---@param on_node_event loop.scheduler.NodeEventFn
---@param on_exit loop.scheduler.exit_fn
function Scheduler:_run_node(id, on_node_event, on_exit)
    if self._terminating then
        on_exit(false, "interrupt")
        return
    end

    -- Skip if already completed in this run
    if self._done[id] then
        on_exit(true, "node")
        return
    end

    -- Join inflight execution if already running
    if self._inflight[id] then
        table.insert(self._inflight[id], { on_node_event = on_node_event, on_exit = on_exit })
        return
    end

    local node = self._nodes[id]
    if not node then
        on_exit(false, "invalid_node", id)
        return
    end

    if self._visiting[id] then
        on_exit(false, "cycle", id)
        return
    end

    self._visiting[id] = true
    self._inflight[id] = { { on_node_event = on_node_event, on_exit = on_exit } }

    -- Run dependencies
    self:_run_deps(node.deps or {}, node.order or "sequence", function(ok, trigger, param)
        self._visiting[id] = nil
        
        if not ok or self._terminating then
            local listeners = self._inflight[id]
            self._inflight[id] = nil
            local final_trigger = self._terminating and "interrupt" or trigger
            for _, cb in ipairs(listeners) do 
                cb.on_exit(false, final_trigger, param) 
            end
            return
        end

        -- Start leaf execution
        self:_broadcast_event(id, "start")

        self:_run_leaf(id, function(ok2, trigger2, param2)
            if ok2 then self._done[id] = true end
            
            self:_broadcast_event(id, "stop")
            
            local listeners = self._inflight[id]
            self._inflight[id] = nil
            for _, cb in ipairs(listeners) do 
                cb.on_exit(ok2, trigger2, param2) 
            end
        end)
    end)
end

---@param deps loop.scheduler.NodeId[]
---@param order "sequence"|"parallel"
---@param on_exit loop.scheduler.exit_fn
function Scheduler:_run_deps(deps, order, on_exit)
    if #deps == 0 then return on_exit(true, "node") end
    
    if order == "parallel" then
        local remaining = #deps
        local failed = false
        for _, dep in ipairs(deps) do
            -- Pass the primary observer down to deps to maintain event flow
            self:_run_node(dep, self._current_node_event, function(ok, trigger, param)
                if failed then return end
                if not ok then
                    failed = true
                    on_exit(false, trigger, param)
                    return
                end
                remaining = remaining - 1
                if remaining == 0 then on_exit(true, "node") end
            end)
        end
    else
        local i = 1
        local function next_dep()
            if i > #deps then return on_exit(true, "node") end
            self:_run_node(deps[i], self._current_node_event, function(ok, trigger, param)
                if not ok then return on_exit(false, trigger, param) end
                i = i + 1
                next_dep()
            end)
        end
        next_dep()
    end
end

---@param id loop.scheduler.NodeId
---@param on_exit loop.scheduler.exit_fn
function Scheduler:_run_leaf(id, on_exit)
    self._pending_running = self._pending_running + 1
    local my_run = self._run_id

    local ctl, err = self._start_node(id, function(ok, reason)
        if my_run ~= self._run_id then return end
        
        self._running[id] = nil
        self._pending_running = math.max(0, self._pending_running - 1)
        
        on_exit(ok, "node", reason)
        self:_check_termination_complete()
    end)

    if not ctl then
        self._pending_running = math.max(0, self._pending_running - 1)
        on_exit(false, "node", err or "Failed to start node")
        self:_check_termination_complete()
        return
    end
    self._running[id] = ctl
end

return Scheduler