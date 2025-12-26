local M             = {}

local taskmgr       = require("loop.task.taskmgr")
local resolver      = require("loop.tools.resolver")
local notifications = require("loop.notifications")
local TaskScheduler = require("loop.task.TaskScheduler")
local ItemTreeComp  = require("loop.comp.ItemTree")
local config        = require("loop.config")


_status_node_id = "\027STATUS\027"

-- Example state-to-highlight mapping
local _highlights = {
    pending = "LoopPluginTaskPending",
    running = "LoopPluginTaskRunning",
    success = "LoopPluginTaskSuccess",
    warning = "LoopPluginTaskWarning",
    failure = "LoopPluginTaskFailure",
}

vim.api.nvim_set_hl(0, _highlights.pending, { link = "Comment" })
vim.api.nvim_set_hl(0, _highlights.running, { link = "DiffChange" })
vim.api.nvim_set_hl(0, _highlights.success, { link = "DiffAdd" })
vim.api.nvim_set_hl(0, _highlights.warning, { link = "WarningMsg" })
vim.api.nvim_set_hl(0, _highlights.failure, { link = "ErrorMsg" })

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
---@return loop.comp.ItemTree,loop.PageController
local function _create_progress_page(page_manager_fact)
    local symbols = config.current.window.symbols
    ---@type loop.comp.ItemTree.InitArgs
    local comp_args = {
        formatter = function(id, data, out_highlights)
            if data.log_message then
                if data.log_level == vim.log.levels.ERROR then
                    table.insert(out_highlights, { group = _highlights.failure })
                end
                return data.log_message
            end
            hl = _highlights.pending
            local icon = symbols.waiting
            if data.event == "start" then
                icon = symbols.running
                hl = _highlights.running
            elseif data.event == "stop" then
                if data.success then
                    icon = symbols.success
                    hl = _highlights.success
                else
                    icon = symbols.failure
                    hl = _highlights.failure
                end
            end
            local prefix = "[" .. icon .. "]"
            table.insert(out_highlights, { group = hl, end_col = #prefix })
            local text = prefix .. data.name
            if data.error_msg then
                text = text .. '\n' .. data.error_msg
            end
            return text
        end,
    }
    local comp = ItemTreeComp:new(comp_args)

    if _current_progress_pmgr then
        _current_progress_pmgr.delete_all_groups(true)
    end

    _current_progress_pmgr = page_manager_fact()
    local group = _current_progress_pmgr.add_page_group("status", "Status")
    assert(group, "page mgr error")
    local page_data = group.add_page({
        id = "status",
        type = "comp_buf",
        label = "Status",
        buftype = "status",
        activate = true,
    })
    assert(page_data)
    page_data.comp_buf.disable_change_events()
    comp:link_to_buffer(page_data.comp_buf)
    return comp, page_data.page
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
        local symbols = config.current.window.symbols

        local progress_info = {
            ---@type loop.comp.ItemTree|nil
            tree_comp = nil,
            ---@type loop.PageData|nil
            page_data = nil
        }
        progress_info.tree_comp, progress_info.page = _create_progress_page(page_manager_fact)
        progress_info.page.set_ui_flags(symbols.waiting)

        local function report_status(msg, is_error)
            progress_info.tree_comp:upsert_item({ id = _status_node_id, data = { log_message = msg, log_level = is_error and vim.log.levels.ERROR or nil } })
            progress_info.page.set_ui_flags(symbols.failure)
        end

        if #all_tasks == 0 then
            report_status("No tasks found", true)
            return
        end

        taskmgr.save_last_task_name(root_name, config_dir)

        local node_tree, used_tasks, plan_error_msg = _scheduler:generate_task_plan(all_tasks, root_name)
        if not node_tree or not used_tasks then
            report_status(plan_error_msg or "Failed to build task plan", true)
            return
        end

        progress_info.tree_comp:upsert_item({ id = _status_node_id, data = { log_message = "Resolving macros" } })

        -- Resolve macros only on the tasks that will be used
        resolver.resolve_macros(used_tasks, function(resolve_ok, resolved_tasks, resolve_error)
            if not resolve_ok or not resolved_tasks then
                report_status(resolve_error or "Failed to resolve macros in tasks", true)
                return
            end
            report_status("Scheduling tasks")
            -- Start the real execution
            _scheduler:start(
                resolved_tasks,
                root_name,
                page_manager_fact,
                function() -- on start
                    progress_info.tree_comp:clear_items()
                    _convert_task_tree(node_tree, progress_info.tree_comp)
                    progress_info.page.set_ui_flags(config.current.window.symbols.running)
                end,
                function(name, event, success, reason) -- on stask event
                    local tree_comp = progress_info.tree_comp
                    if tree_comp then
                        local item = tree_comp:get_item(name)
                        if item then
                            item.data.event = event
                            item.data.success = success
                            item.data.error_msg = (not success) and reason or nil
                            tree_comp:refresh_content()
                        end
                    end
                end,
                function(success, reason) -- on exit
                    progress_info.page.set_ui_flags(success and symbols.success or symbols.failure)
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
        _scheduler:terminate()
    end
end

return M
