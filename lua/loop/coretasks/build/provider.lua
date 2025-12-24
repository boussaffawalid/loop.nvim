local run = require('loop.coretasks.build.build')

---@type loop.TaskProvider
local provider = {
    get_task_schema = function()
        local schema = require('loop.coretasks.build.schema')
        return schema
    end,
    get_task_templates = function(config)
        local templates = require('loop.coretasks.build.templates')
        return templates
    end,
    start_one_task = run.start_build
}

return provider
