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
    persistence = {
        shada = false,
        undo = false,
    },
    window = {
        symbols = {
            change  = "●",
            success = "✓",
            failure = "✗",
            waiting = "⧗",
            running = "▶",
        },
    },
    macros = require("loop.task.macros"),
    debug = false,
    autosave_interval = 5, -- 5 minutes
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
        { vimcmd = "Loop workspace info",      help = "Show information about the current workspace" },
        { vimcmd = "Loop workspace create",    help = "Create a new workspace in the current working directory" },
        { vimcmd = "Loop workspace open",      help = "Open the workspace in the current working directory" },
        { vimcmd = "Loop workspace save",      help = "Save workspace buffers (as defined in the workspace configuration)" },
        { vimcmd = "Loop workspace configure", help = "Create/Open the workspace configuration file" },
        { vimcmd = "Loop toggle",              help = "Toggle Loop window" },
        { vimcmd = "Loop show",                help = "Show Loop window" },
        { vimcmd = "Loop hide",                help = "Hide Loop window" },
        { vimcmd = "Loop page",                help = "Select the page shown in the Loop window" },
        { vimcmd = "Loop page open",           help = "Select and open a page in the current window" },
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
        { "terminate", "Terminate running tasks" },
    }

    for _, cmd in ipairs(other_task_cmds) do
        table.insert(all_cmds, {
            vimcmd = "Loop task " .. cmd[1],
            help = cmd[2],
        })
    end

    table.insert(all_cmds,
        { vimcmd = "Loop task configure", help = "Configure tasks or check the current configuration" })
    for _, name in ipairs(workspace.configurable_task_types()) do
        table.insert(all_cmds, { vimcmd = "Loop task configure " .. name, help = "Configure " .. name .. " tasks module" })
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
