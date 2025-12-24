local run = require('loop.coretasks.run.run')

---@type loop.TaskProvider
local provider = {

    get_task_schema = function()
        local schema = require('loop.coretasks.run.schema')
        return schema
    end,
    get_task_templates = function(config)
        local templates = require('loop.coretasks.run.templates')
        return templates
    end,
    start_one_task = run.start_app
}

return provider
