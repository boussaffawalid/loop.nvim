local class = require("loop.tools.class")
local Scheduler = require("loop.tools.Scheduler")
local taskmgr = require("loop.task.taskmgr")

---@class loop.TaskPlan
---@field tasks loop.Task[]
---@field root string
---@field dry_run boolean
---@field dry_run_report string[]|nil
---@field page_manager_fact loop.PageManagerFactory
---@field on_exit fun(success:boolean, reason?:string,dry_run_report?:string[]|nil)

---@class loop.TaskScheduler
---@field new fun(self:loop.TaskScheduler):loop.TaskScheduler
---@field _scheduler loop.tools.Scheduler | nil
---@field _pending_plan loop.TaskPlan | nil
---@field _page_manager loop.PageManager[]
local TaskScheduler = class()

--- Create a new TaskScheduler
function TaskScheduler:init()
    self._scheduler = nil
    self._pending_plan = nil
    self._page_managers = {}
end

---@param plan loop.TaskPlan
---@return table<string, loop.Task>? name_to_task
---@return loop.scheduler.Node[]? nodes
---@return string? error_msg
local function validate_and_build_nodes(plan)
    local name_to_task = {}
    local nodes = {}

    for _, task in ipairs(plan.tasks) do
        if name_to_task[task.name] then
            return nil, nil, "Duplicate task name: " .. task.name
        end
        name_to_task[task.name] = task
        table.insert(nodes, {
            id = task.name,
            deps = task.depends_on or {},
            order = task.depends_order or "sequence",
        })
    end

    if not name_to_task[plan.root] then
        return nil, nil, "Root task '" .. plan.root .. "' not found among provided tasks"
    end

    return name_to_task, nodes, nil
end

---@param plan loop.TaskPlan
function TaskScheduler:_run_plan(plan)
    local name_to_task, nodes, err = validate_and_build_nodes(plan)
    if err or not name_to_task or not nodes then
        vim.schedule_wrap(plan.on_exit)(false, err)
        return
    end

    ---@type loop.scheduler.StartNodeFn
    local function start_node(id, on_node_exit)
        local task = name_to_task[id] --[[@as loop.Task]]

        if plan.dry_run then
            plan.dry_run_report = plan.dry_run_report or {}
            table.insert(plan.dry_run_report, task.name)
            on_node_exit(true)
            return { terminate = function() end }
        end

        local provider = taskmgr.get_provider(task.type)
        if not provider then
            on_node_exit(false, "No provider registered for task type: " .. task.type)
            return { terminate = function() end }
        end

        local exit_handler = vim.schedule_wrap(function(success, reason)
            on_node_exit(success, reason)
        end)

        local page_mgr = plan.page_manager_fact()
        table.insert(self._page_managers, page_mgr)
        local control, start_err = provider.start_one_task(task, page_mgr, exit_handler)

        if not control then
            on_node_exit(false, start_err or ("Failed to start task '" .. task.name .. "'"))
            return { terminate = function() end }
        end

        return control
    end

    local scheduler = Scheduler:new(nodes, start_node)

    local final_cb = vim.schedule_wrap(plan.on_exit)

    scheduler:start(plan.root, function(success, trigger, param)
        local reason
        if trigger == "cycle" then
            reason = "Task dependency loop detected in task: " .. tostring(param)
        elseif trigger == "invalid_node" then
            reason = "Invalid task name: " .. tostring(param)
        elseif trigger == "interrupt" then
            reason = "Task interrupted"
        else
            reason = param or "Task failed"
        end

        final_cb(success, reason, plan.dry_run_report)

        if self._pending_plan then
            self:_start_current_plan()
        end

        if self._scheduler == scheduler then
            self._scheduler = nil
        end
    end)

    self._scheduler = scheduler
end

function TaskScheduler:_start_current_plan()
    local plan = self._pending_plan
    if not plan then return end
    self._pending_plan = nil
    -- drop old pages
    for _, pm in ipairs(self._page_managers) do
        pm.delete_all_groups(true)
    end
    self._page_managers = {}
    -- Normalize
    plan.dry_run = plan.dry_run == true
    -- Run plan
    self:_run_plan(plan)
end

---@param tasks loop.Task[]
---@param root string
---@param dry_run? boolean
---@param page_manager_fact loop.PageManagerFactory
---@param on_exit? fun(success:boolean, reason?:string,dry_run_report?:string[]|nil)
function TaskScheduler:start(tasks, root, dry_run, page_manager_fact, on_exit)
    on_exit = on_exit or function(success, reason) end
    dry_run = dry_run == true

    self._pending_plan = {
        tasks = tasks,
        root = root,
        dry_run = dry_run,
        page_manager_fact = page_manager_fact,
        on_exit = on_exit,
    }

    if not self._scheduler or self._scheduler:is_terminated() then
        self:_start_current_plan()
    elseif self._scheduler:is_running() or self._scheduler:is_terminating() then
        self._scheduler:terminate()
        -- Pending plan will start automatically after termination
    end
end

function TaskScheduler:terminate()
    if self._scheduler and (self._scheduler:is_running() or self._scheduler:is_terminating()) then
        self._scheduler:terminate()
    end
end

---@return boolean
function TaskScheduler:is_running()
    return self._scheduler and self._scheduler:is_running() or false
end

---@return boolean
function TaskScheduler:is_terminating()
    return self._scheduler and self._scheduler:is_terminating() or false
end

return TaskScheduler
