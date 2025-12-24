---@type loop.WorkspaceConfig
return {
    __order = {"name", "save", "persistence"},
    name = "",
    save = {
        __order = {"include", "exclude", "follow_symlinks"},
        include = { "**/*.lua" },
        exclude = { "**/test/**" },
        follow_symlinks = false,
    },
    persistence = {
        __order = {"shada", "undo", "session"},
        shada = true,
        undo = true,
        session = true,
    },
}
