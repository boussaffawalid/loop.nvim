local field_order = { "name", "type", "command", "cwd", "quickfix_matcher", "depends_on" }

---@type loop.taskTemplate[]
return {
    {
        name = "Build",
        task = {
            __order = field_order,
            name = "Build",
            type = "build",
            command = "true",
            cwd = "${wsdir}",
            quickfix_matcher = "",
            depends_on = {},
        },
    },
    {
        name = "Lua check",
        task = {
            __order = field_order,
            name = "Check",
            type = "build",
            command = "luacheck ${wsdir}",
            cwd = "${wsdir}",
            quickfix_matcher = "luacheck",
            depends_on = {},
        },
    },
    {
        name = "Build c++ file",
        task = {
            __order = field_order,
            name = "Build",
            type = "build",
            command = "g++ -g -std=c++23 ${file:cpp} -o ${fileroot}.out",
            cwd = "${wsdir}",
            quickfix_matcher = "gcc",
            depends_on = {},
        },
    }
}
