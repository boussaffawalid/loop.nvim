local M             = {}

local taskmgr       = require("loop.task.taskmgr")
local resolver      = require("loop.tools.resolver")
local notifications = require("loop.notifications")
local TaskScheduler = require("loop.task.TaskScheduler")

---@type loop.TaskScheduler
local _scheduler    = TaskScheduler:new()

-- Usage example:
-- local ts = TaskScheduler:new()
-- local tree, err = ts:generate_task_plan_tree(tasks, "root_task")
-- if not err then
--     print_task_tree(tree)
-- else
--     print("Error:", err)
-- end
---@param node table Task node from generate_task_plan_tree
---@param prefix? string Internal use for indentation
---@param is_last? boolean Internal use to determine tree branch
local function print_task_tree(node, prefix, is_last)
    prefix = prefix or ""
    is_last = is_last or true

    local branch = is_last and "└─ " or "├─ "
    local line = prefix .. branch .. node.name .. " (" .. (node.order or "sequence") .. ")"
    local new_prefix = prefix .. (is_last and "   " or "│  ")
    if node.deps then
        for i, child in ipairs(node.deps) do
            line = line .. '\n' .. print_task_tree(child, new_prefix, i == #node.deps)
        end
    end
    return line
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

        local node_tree, used_tasks, plan_error_msg = _scheduler:generate_task_plan(all_tasks, root_name)
        if not node_tree or not used_tasks then
            notifications.notify(plan_error_msg or "Failed to build task plan", vim.log.levels.ERROR)
            return
        end

        notifications.notify("Task plan: \n" .. print_task_tree(node_tree))

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
