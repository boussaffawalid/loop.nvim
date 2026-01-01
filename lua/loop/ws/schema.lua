local schema = {
    type = "object",
    required = { "name", "save" },
    properties = {
        name = {
            type = { "string" },
            default = "",
            description = "Optional name/identifier for this configuration entry",
        },
        save = {
            type = { "object", "nil" },
            description = "File saving/filtering options",
            default = {},
            properties = {
                include = {
                    type = { "array" },
                    description = "Glob patterns for files to include when saving",
                    items = { type = "string" },
                },
                exclude = {
                    type = { "array" },
                    description = "Glob patterns for files/directories to exclude",
                    items = { type = "string" },
                },
                follow_symlinks = {
                    type = { "boolean" },
                    description = "Whether to follow symbolic links when scanning",
                },
            },
            additionalProperties = false,
        },
    },
    additionalProperties = false,
}

return schema
