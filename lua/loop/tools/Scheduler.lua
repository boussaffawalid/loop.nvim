local class = require("loop.tools.class")

---@alias loop.scheduler.exit_trigger "cycle"|"invalid_node"|"interrupt"|"node"
---@alias loop.scheduler.exit_fn fun(success:boolean,trigger:loop.scheduler.exit_trigger,param:any)

---@alias loop.scheduler.NodeId string

---@alias loop.scheduler.StartNodeFn fun(id: loop.scheduler.NodeId, on_exit: fun(ok:boolean, reason:string|nil)): { terminate:fun() }|nil, string|nil

---@class loop.scheduler.Node
---@field id loop.scheduler.NodeId
---@field deps loop.scheduler.NodeId[]?
---@field order "sequence"|"parallel"|nil

---@class loop.tools.Scheduler
---@field new fun(self:loop.tools.Scheduler,nodes:loop.scheduler.Node[],start_node:loop.scheduler.StartNodeFn):loop.tools.Scheduler
---@field _nodes table<loop.scheduler.NodeId, loop.scheduler.Node>
---@field _start_node loop.scheduler.StartNodeFn
---@field _running table<loop.scheduler.NodeId, { terminate:fun() }>
---@field _visited table<loop.scheduler.NodeId, boolean>
---@field _pending_running integer
---@field _terminated boolean
---@field _terminating boolean
---@field _pending_start { root:loop.scheduler.NodeId, on_exit:loop.scheduler.exit_fn }|nil
---@field _run_id integer
local Scheduler = class()

--──────────────────────────────────────────────────────────────────────────────
-- Constructor
--──────────────────────────────────────────────────────────────────────────────

---@param nodes loop.scheduler.Node[]
---@param start_node loop.scheduler.StartNodeFn
function Scheduler:init(nodes, start_node)
    self._nodes = {}
    for _, n in ipairs(nodes) do
        self._nodes[n.id] = n
    end

    self._start_node = start_node

    self._running = {}
    self._visited = {}
    self._pending_running = 0

    self._terminated = true
    self._terminating = false
    self._pending_start = nil
    self._run_id = 0
end

--──────────────────────────────────────────────────────────────────────────────
-- Public API
--──────────────────────────────────────────────────────────────────────────────

---@param root loop.scheduler.NodeId
---@param on_exit loop.scheduler.exit_fn
function Scheduler:start(root, on_exit)
    self._pending_start = { root = root, on_exit = on_exit }

    if self._terminating then return end
    if not self._terminated then
        self:_begin_termination()
        return
    end

    self:_start_pending()
end

function Scheduler:terminate()
    if self._terminated or self._terminating then return end
    self:_begin_termination()
end

--──────────────────────────────────────────────────────────────────────────────
-- Internal: lifecycle
--──────────────────────────────────────────────────────────────────────────────

function Scheduler:_begin_termination()
    if self._terminating then return end
    self._terminating = true

    for _, ctl in pairs(self._running) do
        ctl.terminate()
    end

    self:_check_termination_complete()
end

function Scheduler:_check_termination_complete()
    if self._terminated then return end
    if self._pending_running > 0 then return end

    self._terminating = false
    self._terminated = true
    self._running = {}
    self._visited = {}

    self:_start_pending()
end

function Scheduler:_start_pending()
    local p = self._pending_start
    if not p then return end
    self._pending_start = nil

    self._run_id = self._run_id + 1
    local my_run = self._run_id

    self._terminated = false
    self._visited = {}
    self._running = {}
    self._pending_running = 0

    self:_run_node(p.root, function(ok, trigger, param)
        if my_run ~= self._run_id then return end
        p.on_exit(ok, trigger, param)
        self:_check_termination_complete()        
    end)
end

--──────────────────────────────────────────────────────────────────────────────
-- Internal: graph execution
--──────────────────────────────────────────────────────────────────────────────

---@param id loop.scheduler.NodeId
---@param on_exit loop.scheduler.exit_fn
function Scheduler:_run_node(id, on_exit)
    if self._terminating then
        on_exit(false, "interrupt")
        return
    end
    if self._visited[id] then
        -- dont change the format if this text, it's parsed by higher level classes
        on_exit(false, "cycle", id)
        return
    end
    self._visited[id] = true

    local node = self._nodes[id]
    if not node then
        on_exit(false, "invalid_node", id)
        return
    end

    self:_run_deps(node.deps or {}, node.order or "sequence", function(ok, trigger, param)
        if not ok then
            on_exit(false, trigger, param)
            return
        end
        self:_run_leaf(id, on_exit)
    end)
end

---@param deps loop.scheduler.NodeId[]
---@param order "sequence"|"parallel"
---@param on_exit loop.scheduler.exit_fn
function Scheduler:_run_deps(deps, order, on_exit)
    if #deps == 0 then
        on_exit(true, "node")
        return
    end
    if self._terminating then
        on_exit(false, "interrupt")
        return
    end
    if order == "parallel" then
        local remaining = #deps
        local failed = false

        for _, dep in ipairs(deps) do
            self:_run_node(dep, function(ok, trigger, param)
                if failed then return end
                if not ok then
                    failed = true
                    on_exit(false, trigger, param)
                    return
                end
                remaining = remaining - 1
                if remaining == 0 then
                    on_exit(true, "node")
                end
            end)
        end
    else
        local i = 1
        local function next_dep()
            if i > #deps then
                on_exit(true, "node")
                return
            end
            self:_run_node(deps[i], function(ok, trigger, param)
                if not ok then
                    on_exit(false, trigger, param)
                    return
                end
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

        self:_check_termination_complete()
        on_exit(ok, "node", reason)
    end)

    if not ctl then
        self._pending_running = math.max(0, self._pending_running - 1)
        self:_check_termination_complete()
        on_exit(false, "node", err or "Failed to start node")
        return
    end

    self._running[id] = ctl
end

function Scheduler:is_running()
    return not self._terminated and not self._terminating
end

function Scheduler:is_terminated()
    return self._terminated
end

function Scheduler:is_terminating()
    return self._terminating
end

return Scheduler
