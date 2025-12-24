local schema = {
    type = "object",
    required = { "command" },
    properties = {
        command = {
            type = { "string" },
            description = "vim command to run"
        },
    },
}

return schema
