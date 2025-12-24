local schema = {
    required = { "command", "cwd" },

    properties = {
        command = {
            description = "Command to run (string or array of strings).",
            oneOf = {
                { type = "string", minLength = 1 },
                {
                    type = "array",
                    minItems = 1,
                    items = { type = "string", minLength = 1 },
                },
                { type = "null" },
            },
        },

        cwd = {
            type = { "string", "null" },
            description = "working directory",
        },

        env = {
            type = { "object", "null" },
            additionalProperties = { type = "string" },
            description = "Optional environment variables",
        },
    },
}

return schema
