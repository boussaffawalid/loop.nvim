local M             = {}

local taskmgr       = require("loop.task.taskmgr")
local resolver      = require("loop.tools.resolver")
local notifications = require("loop.notifications")
local TaskScheduler = require("loop.task.TaskScheduler")

---@type loop.TaskScheduler
local _scheduler    = TaskScheduler:new()

--- Filter tasks to only those reachable from the root (i.e., will actually run)
---@param all_tasks loop.Task[]
---@param used_names string[]
---@return loop.Task[]
local function filter_used_tasks(all_tasks, used_names)
    local name_set = {}
    for _, name in ipairs(used_names) do
        name_set[name] = true
    end

    local filtered = {}
    for _, task in ipairs(all_tasks) do
        if name_set[task.name] then
            table.insert(filtered, task)
        end
    end
    return filtered
end

--- Collect the list of task names that were actually started during a dry run
---@param dry_tasks loop.Task[]
---@param root_name string
---@param on_dry_complete fun(result: {success:boolean, tasks:string[], errors:string[]})
local function perform_dry_run(dry_tasks, root_name, on_dry_complete)
    local errors = {}

    local tmp_scheduler = TaskScheduler:new()
    tmp_scheduler:start(
        dry_tasks,
        root_name,
        true, -- dry run
        ---@diagnostic disable-next-line: param-type-mismatch
        nil, -- page_manager not needed for dry run
        function(success, reason, dry_run_report)
            if not success then
                table.insert(errors, reason or "Dry run failed")
            end
            on_dry_complete({
                success = success and #errors == 0,
                tasks = dry_run_report or {},
                errors = errors,
            })
        end
    )
end

---@param config_dir string
---@param page_manager_fact loop.PageManagerFactory
---@param mode "task"|"repeat"
---@param task_name string|nil
function M.run_task(config_dir, page_manager_fact, mode, task_name)
    taskmgr.get_or_select_task(config_dir, mode, task_name, function(root_name, all_tasks)
        if not root_name or not all_tasks then
            return
        end

        taskmgr.save_last_task_name(root_name, config_dir)

        if #all_tasks == 0 then
            notifications.notify({ "No tasks found" }, vim.log.levels.WARN)
            return
        end

        -- Step 1: Perform a dry run to discover exactly which tasks will execute
        perform_dry_run(all_tasks, root_name, function(dry_result)
            if not dry_result.success then
                local msg = { "Failed to start task '" .. tostring(root_name) .. "'" }
                if dry_result.errors then                    
                    if #dry_result.errors == 1 then
                        table.insert(msg, "  " .. dry_result.errors[1])
                    elseif #dry_result.errors > 1 then
                        for _, err in ipairs(dry_result.errors) do
                            table.insert(msg, "• " .. err)
                        end
                    end
                end
                notifications.notify(msg, vim.log.levels.ERROR)
                return
            end

            -- Optional preview of what will run
            if #dry_result.tasks > 1 then
                local preview_msg = string.format(
                    "Will run %d tasks: %s",
                    #dry_result.tasks,
                    table.concat(dry_result.tasks, ", ")
                )
                notifications.notify({ preview_msg }, vim.log.levels.INFO)
            end

            -- Step 2: Filter to only the tasks that will actually run
            local used_tasks = filter_used_tasks(all_tasks, dry_result.tasks)

            -- Step 3: Resolve macros only on the tasks that will be used
            resolver.resolve_macros(used_tasks, function(resolve_ok, resolved_tasks, resolve_error)
                if not resolve_ok or not resolved_tasks then
                    notifications.notify({
                        resolve_error or "Failed to resolve macros in tasks"
                    }, vim.log.levels.ERROR)
                    return
                end

                -- Step 4: Start the real execution
                _scheduler:start(
                    resolved_tasks,
                    root_name,
                    false, -- dry_run = false
                    page_manager_fact,
                    function(success, reason)
                        if success then
                            notifications.notify({
                                string.format("Task completed successfully: %s", root_name)
                            }, vim.log.levels.INFO)
                        else
                            local msg = string.format("Task failed: %s", root_name)
                            if reason then
                                msg = msg .. " (" .. reason .. ")"
                            end
                            notifications.notify({ msg }, vim.log.levels.ERROR)
                        end
                    end
                )
            end)
        end)
    end)
end

--- Check if a task plan is currently running or terminating
---@return boolean
function M.have_running_task()
    return _scheduler:is_running() or _scheduler:is_terminating()
end

--- Terminate the currently running task plan (if any)
function M.terminate_tasks()
    if _scheduler:is_running() or _scheduler:is_terminating() then
        notifications.notify({ "Terminating tasks" }, vim.log.levels.INFO)
        _scheduler:terminate()
    end
end

return M
