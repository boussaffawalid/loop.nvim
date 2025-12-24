local M = {}

require("loop.config")
local notifications = require('loop.notifications')
local taskmgr = require("loop.task.taskmgr")
local window = require("loop.ui.window")
local wsinfo = require("loop.wsinfo")
local runner = require("loop.task.runner")
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local jsonschema = require('loop.tools.jsonschema')
local filetools = require('loop.tools.file')
local persistence = require('loop.persistence')

local _init_done = false
local _init_err_msg = "init() not called"

---@type string?
local _workspace_dir = nil

---@type loop.WorkspaceConfig?
local _workspace_config = nil

local _save_timer = nil

local function _get_ws_dir_or_warn()
    if not _workspace_dir then
        notifications.notify("No active workspace", vim.log.levels.WARN)
        return
    end
    return _workspace_dir
end

local function _get_config_dir(workspace_dir)
    local dir = vim.fs.joinpath(workspace_dir, ".nvimloop")
    return dir
end

local function _is_workspace_dir(dir)
    local config_dir = _get_config_dir(dir)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(config_dir)
    return stat and stat.type == "directory"
end

local function _save_workspace()
    if not _workspace_dir then
        return false
    end
    assert(_init_done, _init_err_msg)
    local config_dir = _get_config_dir(_workspace_dir)
    window.save_settings(config_dir)
    taskmgr.save_provider_states(config_dir)
end

---@param quiet? boolean
local function _close_workspace(quiet)
    runner.terminate_tasks()

    _save_workspace()

    persistence.close()

    if not quiet then notifications.notify("Workspace closed") end
    _workspace_dir = nil
    wsinfo.set_ws_info(nil)
end

---@param config_dir any
---@return boolean
---@return string?
local function _init_or_open_ws_config(config_dir)
    local config_file = vim.fs.joinpath(config_dir, "workspace.json")
    if not filetools.file_exists(config_file) then
        jsontools.save_to_file(config_file, require('loop.wsconfig.template'))
    end
    local winid = uitools.smart_open_file(config_file)
    uitools.move_to_first_occurence(winid, '"name": "')
    return true, config_file
end

---@param config_dir string
---@return loop.WorkspaceConfig?,string[]?
local function _load_workspace_config(config_dir)
    local config_file = vim.fs.joinpath(config_dir, "workspace.json")
    if not filetools.file_exists(config_file) then
        local default_config = vim.deepcopy(require('loop.wsconfig.template'))
        return default_config
    end
    local loaded, data_or_err = jsontools.load_from_file(config_file)
    if not loaded then
        ---@cast data_or_err string
        return nil, { data_or_err }
    end
    local config = data_or_err
    local schema = require('loop.wsconfig.schema')
    local errors = jsonschema.validate(schema, config)
    if errors then
        return nil, errors
    end
    return config
end

---@param dir string
---@param quiet? boolean
---@return boolean
---@return string[]|nil
---@return boolean? --- is config error
---@return string? -- config_dir where the error is
local function _load_workspace(dir, quiet)
    assert(_init_done, _init_err_msg)

    dir = dir or vim.fn.getcwd()
    dir = vim.fn.fnamemodify(dir, ":p")

    if dir == _workspace_dir then
        if not quiet then
            notifications.notify("Workspace is already open")
            return true
        end
        return true
    end

    if _workspace_dir and dir ~= _workspace_dir then
        return false, { "Another workspace is already open" }
    end

    if not _is_workspace_dir(dir) then
        return false, { "No workspace in " .. dir }
    end

    local config_dir = _get_config_dir(dir)
    local ws_config, config_errors = _load_workspace_config(config_dir)
    if not ws_config then
        return false, config_errors, true, config_dir
    end

    _workspace_dir = dir
    _workspace_config = ws_config

    wsinfo.set_ws_info(dir)

    persistence.open(config_dir, ws_config.persistence)

    window.load_settings(config_dir)

    taskmgr.on_workspace_loaded(dir, config_dir)

    if not _save_timer then
        -- Create and start the repeating timer
        ---@diagnostic disable-next-line: undefined-field
        _save_timer = vim.loop.new_timer()
        local save_frequency = 5 * 60 * 1000 -- every 5 minutes (in ms)
        _save_timer:start(
            save_frequency,                  -- initial delay
            save_frequency,                  -- frequency
            vim.schedule_wrap(_save_workspace)
        )
    end

    return true, nil
end

function M.create_workspace(dir)
    assert(_init_done, _init_err_msg)
    if _workspace_dir then
        if dir == _workspace_dir then
            notifications.notify("Workspace already exists")
        else
            notifications.notify("Another workspace is already open")
        end
        return false
    end

    dir = dir or vim.fn.getcwd()
    assert(type(dir) == 'string')
    if _is_workspace_dir(dir) then
        notifications.notify("A workspace already exists in " .. dir, vim.log.levels.ERROR)
        return
    end

    local config_dir = _get_config_dir(dir)
    vim.fn.mkdir(config_dir, "p")

    _load_workspace(dir)
    if not _workspace_dir then
        notifications.notify("Failed to create workspace")
        return
    end

    if not _init_or_open_ws_config(config_dir) then
        notifications.notify("Failed to setup configuration file")
    end
end

---@param dir string
---@param at_startup boolean
function M.open_workspace(dir, at_startup)
    assert(_init_done, _init_err_msg)
    dir = dir or vim.fn.getcwd()
    local ok, errors, config_err, config_dir = _load_workspace(dir, at_startup)
    if ok and _workspace_dir then
        notifications.log("Workspace loaded " .. _workspace_dir)
    elseif not at_startup then
        errors = errors or {}
        table.insert(errors, 1, "Failed to load workspace")
        notifications.notify(errors, vim.log.levels.ERROR)
        if config_err then
            _init_or_open_ws_config(config_dir)
        end
    end
end

function M.configure_workspace()
    if not _workspace_dir then
        notifications.notify("No active workspace", vim.log.levels.WARN)
        return
    end
    local ok, configfile = _init_or_open_ws_config()
    if not ok or not configfile then
        notifications.notify("Failed to setup configuration file")
        return
    end
    local read_ok, data_or_err = uitools.smart_read_file(configfile)
    if not read_ok then
        notifications.notify("Workspace configuration error - " .. tostring(data_or_err))
        return
    end
    local config_ok, config_or_err = jsontools.from_string(data_or_err)
    if not config_ok then
        notifications.notify("Workspace configuration is not a valid JSON - " .. tostring(config_or_err))
        return
    end
    local config = config_or_err
    local schema = require('loop.wsconfig.schema')
    local errors = jsonschema.validate(schema, config)
    if errors then
        notifications.notify("Workspace configuration error\n" .. table.concat(errors, '\n'))
    end
end

---@param quiet? boolean
function M.close_workspace(quiet)
    assert(_init_done, _init_err_msg)
    _close_workspace(quiet)
end

---@param args string[]
---@return string[]
function M.workspace_subcommands(args)
    if #args == 0 then
        return { "show", "create", "open", "configure", "close", "save_files" }
    end
    return {}
end

---@param command string|nil
function M.workspace_cmmand(command, ...)
    if not command or command == "" or command == "show" then
        print(_workspace_dir or "No active workspace")
        return
    end
    if command == "create" then
        M.create_workspace()
        return
    end
    if command == "open" then
        M.open_workspace(vim.fn.getcwd(), false)
        return
    end
    if command == "configure" then
        M.configure_workspace()
        return
    end
    if command == "close" then
        M.close_workspace()
        return
    end
    if command == "save_files" then
        M.save_workspace_files()
        return
    end
    notifications.notify("Invalid command: " .. command)
end

function M.get_ws_dir()
    return _workspace_dir
end

---@param args string[]
---@return string[]
function M.task_subcommands(args)
    if #args == 0 then
        return { "run", "repeat", "add", "configure", "terminate" }
    elseif #args == 1 then
        if args[1] == 'add' then
            return taskmgr.task_types()
        elseif args[1] == 'configure' then
            return taskmgr.configurable_task_types()
        end
    end
    return {}
end

---@param command string|nil
---@param arg1 string
---@param arg2? string|nil
function M.task_command(command, arg1, arg2)
    assert(_init_done, _init_err_msg)
    local ws_dir = _get_ws_dir_or_warn()
    if not ws_dir then
        return
    end


    command = command and command:match("^%s*(.-)%s*$") or ""
    command = command ~= "" and command or "run"

    local config_dir = _get_config_dir(ws_dir)
    if command == "run" then
        runner.run_task(config_dir, window.page_manger_factory(), "task", arg1)
    elseif command == "repeat" then
        runner.run_task(config_dir, window.page_manger_factory(), "repeat")
    elseif command == "add" then
        taskmgr.add_task(config_dir, arg1)
    elseif command == "configure" then
        taskmgr.configure(config_dir, arg1)
    elseif command == "terminate" then
        runner.terminate_tasks()
    else
        notifications.notify('Invalid task command: ' .. command)
    end
end

function M.page_subcommands(args)
    if #args == 0 then
        return { "switch", "open" }
    end
    if #args == 1 and (args[1] == "open") then
        local names = window.get_pagegroup_names()
        return vim.tbl_map(vim.fn.fnameescape, names)
    end
    if #args == 2 and (args[1] == "open") then
        local group = args[1]
        local names = window.get_page_names(group)
        return vim.tbl_map(vim.fn.fnameescape, names)
    end
    return {}
end

function M.page_command(command, arg1, arg2)
    if not command or command == "" or command == "switch" then
        M.switch_page()
    elseif command == "open" then
        M.open_page(arg1, arg2)
    else
        notifications.notify("Invalid command: " .. command)
    end
end

function M.show_window()
    assert(_init_done, _init_err_msg)
    window.show_window()
end

function M.hide_window()
    assert(_init_done, _init_err_msg)
    window.hide_window()
end

function M.toggle_window()
    assert(_init_done, _init_err_msg)
    window.toggle_window()
end

function M.switch_page()
    assert(_init_done, _init_err_msg)
    window.switch_page()
end

---@param group_label string|nil
---@param page_pabel string|nil
function M.open_page(group_label, page_pabel)
    assert(_init_done, _init_err_msg)
    window.open_page(vim.api.nvim_get_current_win(), group_label, page_pabel)
end

function M.save_workspace_files()
    assert(_init_done, _init_err_msg)

    local ws_dir = _get_ws_dir_or_warn()
    if not ws_dir then return 0 end

    local dir = vim.fs.normalize(ws_dir)
    if not dir:match("/$") then dir = dir .. "/" end

    local saved = 0
    local saved_paths = {} -- Collect paths for nice notification

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if not uitools.is_regular_buffer(bufnr) then goto continue end
        if not vim.bo[bufnr].modified then goto continue end

        local path = vim.api.nvim_buf_get_name(bufnr)
        if path == "" then goto continue end
        path = vim.fs.normalize(path)

        if not vim.startswith(path, dir) then goto continue end

        local basename = vim.fs.basename(path)
        if basename:match("^%.") then goto continue end

        local has_hidden_parent = false
        for parent in vim.fs.parents(path) do
            local name = vim.fs.basename(parent)
            if name == "" then break end
            if name:match("^%.") then
                has_hidden_parent = true
                break
            end
        end
        if has_hidden_parent then goto continue end

        -- Save the buffer
        vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("silent! write")
        end)

        -- Store relative path for display
        local rel = path:sub(#dir + 1)
        table.insert(saved_paths, rel)

        saved = saved + 1

        ::continue::
    end

    -- Beautiful notification with preview of saved files
    if saved > 0 then
        local max_show = 5
        local shown = math.min(saved, max_show)
        local lines = { ("Saved %d file%s"):format(saved, saved == 1 and "" or "s") }

        for i = 1, shown do
            table.insert(lines, ("  • %s"):format(saved_paths[i]))
        end

        if saved > max_show then
            table.insert(lines, ("  … and %d more"):format(saved - max_show))
        end

        notifications.notify(lines, vim.log.levels.INFO)
    end

    return saved
end

function M.winbar_click(id, clicks, button, mods)
    assert(_init_done, _init_err_msg)
    window.winbar_click(id, clicks, button, mods)
end

function M.init()
    assert(not _init_done, "init alreay done")
    _init_done = true

    window.init()

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            -- Stop the timer if it's still running
            if _save_timer and _save_timer:is_active() then
                _save_timer:stop()
                _save_timer:close()
            end

            if runner.have_running_task() then
                runner.terminate_tasks()
                local max_waits = 100 -- 5 seconds max
                while max_waits > 0 and runner.have_running_task() do
                    max_waits = max_waits - 1
                    vim.wait(50)
                end
            end

            _close_workspace(true)
        end,
    })
end

return M
