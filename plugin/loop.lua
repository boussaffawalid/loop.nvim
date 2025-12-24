-- IMPORTANT: keep this module light for lazy loading

vim.api.nvim_create_user_command("Loop", function(opts)
        require("loop").dispatch(opts)
    end,
    {
        nargs = "*",
        complete = function(arg_lead, cmd_line, _)
            return require("loop").complete(arg_lead, cmd_line)
        end,
        desc = "Loop.nvim management commands",
    })

local function _is_workspace_dir(dir)
    local config_dir = vim.fs.joinpath(dir, ".nvimloop")
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(config_dir)
    return stat and stat.type == "directory"
end

local group = vim.api.nvim_create_augroup("LoopPluginOnVimEnter", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
        local args = vim.fn.argv()
        local has_dir = #args > 0 and vim.fn.isdirectory(args[1]) == 1
        local dir = has_dir and args[1] or vim.fn.getcwd()
        if _is_workspace_dir(dir) then
            require("loop").load_workspace(dir)
        end
    end
})
