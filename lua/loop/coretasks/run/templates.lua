---@type loop.taskTemplate[]
return {
    {
        name = "Run",
        task = {
            __order = { "name", "type", "command", "cwd", "depends_on" },
            name = "Run",
            type = "run",
            command = "true",
            cwd = "${wsdir}",
            depends_on = {},
        },
    },
}
