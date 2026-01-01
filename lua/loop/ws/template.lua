---@type loop.WorkspaceConfig
return {
    __order = {"name", "save", "persistence"},
    name = "",
    save = {
        __order = {"include", "exclude", "follow_symlinks"},
        include = { "**/*" },
        exclude = { },
        follow_symlinks = false,
    },
    --variables = vim.empty_dict()
}
