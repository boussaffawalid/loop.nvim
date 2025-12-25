local M                      = {}

local taskmgr                = require("loop.task.taskmgr")
local resolver               = require("loop.tools.resolver")
local notifications          = require("loop.notifications")
local TaskScheduler          = require("loop.task.TaskScheduler")
local ItemTreeComp           = require("loop.comp.ItemTree")
local config                 = require("loop.config")

---@type loop.TaskScheduler
local _scheduler             = TaskScheduler:new()

---@type loop.PageManager?
local _current_progress_pmgr = nil

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

---@param node table Task node from generate_task_plan_tree
---@param tree_comp loop.comp.ItemTree
---@param parent_id any
local function _convert_task_tree(node, tree_comp, parent_id)
    local name = node.name
    if node.deps and #node.deps > 1 then
        name = name .. " (" .. (node.order or "sequence") .. ")"
    end
    ---@type loop.comp.ItemTree.Item
    local comp_item = {
        id = node.name,
        parent_id = parent_id,
        expanded = true,
        data = {
            name = name
        }
    }
    tree_comp:upsert_item(comp_item)
    if node.deps then
        for _, child in ipairs(node.deps) do
            _convert_task_tree(child, tree_comp, comp_item.id)
        end
    end
end

---@param page_manager_fact loop.PageManagerFactory
---@param plural boolean
local function _create_progress_page(page_manager_fact, plural)
    local symbols = config.current.window.symbols
    ---@type loop.comp.ItemTree.InitArgs
    local comp_args = {
        formatter = function(id, data, out_highlights)
            local icon = symbols.waiting
            if data.event == "start" then
                icon = symbols.running
            elseif data.event == "stop" then
                icon = data.success and symbols.success or symbols.failure
            end
            return icon .. " " .. data.name
        end,
    }
    local comp = ItemTreeComp:new(comp_args)

    if _current_progress_pmgr then
        _current_progress_pmgr.delete_all_groups(true)
    end
    _current_progress_pmgr = page_manager_fact()
    local group = _current_progress_pmgr.add_page_group("status", plural and "Tasks" or "Task")
    local page = group.add_page("status", "Status", true)
    comp:link_to_buffer(page)
    return comp, page
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

        local progress_info = {
            ---@type loop.comp.ItemTree|nil
            tree_comp = nil,
            ---@type loop.BufferController|nil
            page = nil
        }

        -- Resolve macros only on the tasks that will be used
        resolver.resolve_macros(used_tasks, function(resolve_ok, resolved_tasks, resolve_error)
            if not resolve_ok or not resolved_tasks then
                notifications.notify({
                    resolve_error or "Failed to resolve macros in tasks"
                }, vim.log.levels.ERROR)
                return
            end

            -- Start the real execution
            _scheduler:start(
                resolved_tasks,
                root_name,
                page_manager_fact,
                function() -- on start
                    progress_info.tree_comp, progress_info.page = _create_progress_page(page_manager_fact,#all_tasks > 1)
                    _convert_task_tree(node_tree, progress_info.tree_comp)
                    progress_info.page.set_ui_flags(config.current.window.symbols.running)
                    --notifications.notify("Task plan: \n" .. print_task_tree(node_tree))
                end,
                function(name, event, success) -- on stask event
                    local tree_comp = progress_info.tree_comp
                    if tree_comp then
                        local item = tree_comp:get_item(name)
                        if item then
                            item.data.event = event
                            item.data.success = success
                            tree_comp:refresh_content()
                        end
                    end
                end,
                function(success, reason) -- on exit
                    if success then
                        notifications.notify({
                            string.format("Task completed successfully: %s", root_name)
                        }, vim.log.levels.INFO)
                    else
                        local msg = string.format("Task failed: %s", root_name)
                        if reason then
                            local first_line = reason:match("([^\n]*)") -- Get the first line
                            msg = msg .. " (" .. first_line .. ")"
                        end
                        notifications.notify({ msg }, vim.log.levels.ERROR)
                    end
                    if progress_info.page then
                        local symbols = config.current.window.symbols
                        progress_info.page.set_ui_flags(success and symbols.success or symbols.failure)
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
