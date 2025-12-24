-- lua/loop/init.lua
local strtools = require('loop.tools.strtools')

local M = {}

-- Dependencies
local workspace = require("loop.workspace")
local config = require("loop.config")
local notifications = require("loop.notifications")

-----------------------------------------------------------
-- Defaults
-----------------------------------------------------------

---@type loop.Config
local DEFAULT_CONFIG = {
    selector = "builtin",
    window = {
        symbols = {
            change  = "●",
            success = "✓",
            failure = "✗",
        },
    },
    macros = require("loop.task.macros"),
}

-----------------------------------------------------------
-- State
-----------------------------------------------------------

local setup_done = false
local initialized = false

-----------------------------------------------------------
-- Setup (user config only)
-----------------------------------------------------------

---@param opts loop.Config?
function M.setup(opts)
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    config.current = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
    setup_done = true

    M.init()
end

-----------------------------------------------------------
-- Command completion
-----------------------------------------------------------

function M.complete(arg_lead, cmd_line)
    M.init()

    local function filter(strs)
        local out = {}
        for _, s in ipairs(strs or {}) do
            if not vim.startswith(s, '_') and vim.startswith(s, arg_lead) then
                table.insert(out, s)
            end
        end
        return out
    end

    local args = strtools.split_shell_args(cmd_line)
    if cmd_line:match("%s+$") then
        table.insert(args, ' ')
    end

    if #args == 2 then
        local func_names = filter(vim.tbl_keys(_G.LoopWorkspace or {}))
        -- sort because tbl_keys order may change every time
        return vim.fn.sort(func_names)
    elseif #args >= 3 then
        local cmd = args[2]
        local rest = { unpack(args, 3) }
        rest[#rest] = nil

        if cmd == "task" then
            return filter(workspace.task_subcommands(rest))
        elseif cmd == "workspace" then
            return filter(workspace.workspace_subcommands(rest))
        elseif cmd == "page" then
            return filter(workspace.page_subcommands(rest))
        end
    end

    return {}
end

function M.select_command()
    local task_types = require('loop.task.providers').names()

    ---@type loop.tools.Cmd[]
    local all_cmds = {
        { vimcmd = "Loop workspace",            help = "Show current workspace path" },
        { vimcmd = "Loop workspace create",     help = "Create a new workspace in the current working directory" },
        { vimcmd = "Loop workspace open",       help = "Open the workspace form the current working directory" },
        { vimcmd = "Loop workspace configure",  help = "Configure the current working or check the current the current configuration" },
        { vimcmd = "Loop workspace close",      help = "Close the current workspace" },
        { vimcmd = "Loop workspace save_files", help = "Save workspace files" },
        { vimcmd = "Loop toggle",               help = "Toggle Loop window" },
        { vimcmd = "Loop show",                 help = "Show Loop window" },
        { vimcmd = "Loop hide",                 help = "Hide Loop window" },
        { vimcmd = "Loop page",                 help = "Switch page" },
        { vimcmd = "Loop open_page",            help = "Open a page" },
    }

    ------------------------------------------------------------------
    -- Task add subcommands
    ------------------------------------------------------------------
    for _, type in ipairs(task_types) do
        table.insert(all_cmds, {
            vimcmd = "Loop task add " .. type,
            help = "Create a new task of type " .. type,
        })
    end

    ------------------------------------------------------------------
    -- Other task subcommands (ordered)
    ------------------------------------------------------------------
    local other_task_cmds = {
        { "run",       "Run task" },
        { "repeat",    "Repeat last task" },
        { "configure", "Configure tasks or check the current configuration" },
        { "terminate", "Terminate running tasks" },
    }

    for _, cmd in ipairs(other_task_cmds) do
        table.insert(all_cmds, {
            vimcmd = "Loop task " .. cmd[1],
            help = cmd[2],
        })
    end

    require("loop.tools.cmdmenu").select_and_run_command(all_cmds)
end

-----------------------------------------------------------
-- Dispatcher
-----------------------------------------------------------

function M.dispatch(opts)
    M.init()

    local args = strtools.split_shell_args(opts.args)
    local subcmd = args[1]

    if not subcmd or subcmd == "" then
        M.select_command()
        return
    end

    local fn = _G.LoopWorkspace[subcmd]
    if not fn then
        notifications.notify(
            "Invalid command: " .. subcmd,
            vim.log.levels.ERROR
        )
        return
    end

    local rest = { unpack(args, 2) }
    local ok, err = pcall(fn, unpack(rest))
    if not ok then
        notifications.notify(
            "Loop " .. subcmd .. " failed: " .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end

-----------------------------------------------------------
-- Initialization (runs once)
-----------------------------------------------------------

function M.init()
    if initialized then
        return
    end
    initialized = true

    -- Apply defaults if setup() was never called
    if not setup_done then
        config.current = DEFAULT_CONFIG
    end

    workspace.init()

    _G.LoopWorkspace = {
        _winbar_click = workspace.winbar_click,
        toggle = workspace.toggle_window,
        show = workspace.show_window,
        hide = workspace.hide_window,
        page = workspace.page_command,
        workspace = workspace.workspace_cmmand,
        task = workspace.task_command,
    }
end

function M.load_workspace(dir)
    M.init()
    workspace.open_workspace(dir, true)
end

return M
