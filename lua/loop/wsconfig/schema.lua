local schema = {
    type = "object",
    required = { "name", "save", "persistence" },
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
                    type = { "array"},
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
        persistence = {
            type = "object",
            description = "Persistence settings for various Neovim data types",
            required = { "shada", "undo" },
            properties = {
                shada = {
                    type = "boolean",
                    description = "Enable persistence of ShaDa (shared data) file",
                },
                undo = {
                    type = "boolean",
                    description = "Enable undo history persistence",
                },
            },
            additionalProperties = false,
        },
    },
    additionalProperties = false,
}

return schema
