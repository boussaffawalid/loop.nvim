---@type loop.taskTemplate[]
return {
    {
        name = "Vim notification",
        task = {
            __order = { "name", "type", "command", "depends_on" },
            name = "Vim notify",
            type = "vimcmd",
            command = "lua vim.notify('Hello world')",
            depends_on = {},
        },
    },
}
