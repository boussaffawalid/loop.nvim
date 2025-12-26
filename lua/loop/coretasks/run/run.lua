local M = {}

local wsinfo = require('loop.wsinfo')

---@class loop.coretasks.app.Task : loop.Task
---@field command string[]|string|nil
---@field cwd string?
---@field env table<string,string>? # optional environment variables

---@param task loop.coretasks.build.Task
---@param page_manager loop.PageManager
---@param on_exit loop.TaskExitHandler
---@return loop.TaskControl|nil
---@return string|nil
function M.start_app(task, page_manager, on_exit)
    if not task.command then
        return nil, "task.command is required"
    end

    -- Your original args — unchanged, just using the resolved values
    ---@type loop.tools.TermProc.StartArgs
    local start_args = {
        name = task.name or "Unnamed Tool Task",
        command = task.command,
        env = task.env,
        cwd = task.cwd or wsinfo.get_ws_dir(),
        output_handler = nil,
        on_exit_handler = function(code)
            if code == 0 then
                on_exit(true, nil)
            else
                on_exit(false, "Exit code " .. tostring(code))
            end
        end,
    }

    local pagegroup = page_manager.get_page_group(task.type)
    if not pagegroup then
        pagegroup = page_manager.add_page_group(task.type, task.name)
    end
    if not pagegroup then
        return nil, "page manager expired"
    end

    local page_data, err_msg = pagegroup.add_page({
        id = "term",
        type = "term",
        buftype = "term",
        label = task.name,
        term_args = start_args,
        activate = true,
    })

    --add_term_page(task.name, start_args, true)
    local proc = page_data and page_data.term_proc or nil
    if not proc then
        return nil, err_msg
    end

    ---@type loop.TaskControl
    local controller = {
        terminate = function()
            proc:terminate()
        end
    }
    return controller, nil
end

return M
