---@class loop.coretasks.vimcmd.Task : loop.Task
---@field command string


---@type loop.TaskProvider
local provider = {
    get_task_schema = function ()
        local schema = require('loop.coretasks.vimcmd.schema')
        return schema
    end,
    get_task_templates = function(config)
        local templates = require('loop.coretasks.vimcmd.templates')
        return templates
    end,
    start_one_task = function(task, page_manager, on_exit)
        ---@cast task loop.coretasks.vimcmd.Task
        -- require the module
        local call_ok, payload = pcall(function() vim.cmd(task.command) end)

        if not call_ok then
            return nil, "vim command error, " .. tostring(payload)
        end

        vim.schedule(function()
            on_exit(true)
        end)
        ---@type loop.TaskControl
        local controller = {
            terminate = function()
            end
        }
        return controller, nil
    end
}

return provider
