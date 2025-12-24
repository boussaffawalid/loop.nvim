local field_order = { "name", "type", "depends_on", "depends_order" }
---@type loop.TaskProvider
local provider = {

    get_task_schema = function()
        return {}
    end,
    get_task_templates = function(config)
        ---@type loop.taskTemplate[]
        return {
            {
                name = "Sequence run",
                task = {
                    __order = field_order,
                    name = "Composite",
                    type = "composite",
                    depends_on = { "", "" },
                    depends_order = "sequence",
                },
            },
            {
                name = "Parallel run",
                task = {
                    __order = field_order,
                    name = "Composite",
                    type = "composite",
                    depends_on = { "", "" },
                    depends_order = "parallel",
                },
            },
        }
    end,
    start_one_task = function(_, _, on_exit)
        on_exit(true)
        ---@type loop.TaskControl
        return {
            terminate = function()
            end
        }
    end
}

return provider
