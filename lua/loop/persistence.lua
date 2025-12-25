local M = {}

local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')

---@type {config_dir:string,flags:{shada:boolean, undo:boolean, session:boolean}} | nil
local _state = nil

---@type {shadafile:string|nil, undodir:string|nil, undofile:boolean|nil}?
local _originals = nil

local function ensure_dir(path)
    if vim.fn.isdirectory(path) == 0 then
        vim.fn.mkdir(path, "p")
    end
end

-- Completely safe sessionoptions for workspace sessions
local SAFE_SESSIONOPTIONS = "blank,buffers,folds,help,tabpages,winsize"

---@param config_dir string
---@param flags {shada:boolean,undo:boolean,session:boolean}
function M.open(config_dir, flags)
    if not flags then return end
    ensure_dir(config_dir)

    if _state then
        M.close()
    end

    assert(not _state, "Workspace already open")

    _state = {
        flags = flags,
        config_dir = config_dir,
    }
    _originals = {}

    -- === ShaDa Support ===
    if flags.shada then
        vim.cmd("wshada!") -- Save global before switching

        _originals.shadafile = vim.o.shadafile ~= "" and vim.o.shadafile or nil

        local shada_path = vim.fs.joinpath(config_dir, "main.shada")
        vim.opt.shadafile = shada_path

        if filetools.file_exists(shada_path) then
            vim.cmd("rshada!")
        else
            vim.cmd("clearjumps")
            vim.v.hlsearch = 0
            vim.fn.setreg('/', '')
        end
    end

    -- === Undo Support ===
    if flags.undo then
        _originals.undodir = vim.o.undodir
        _originals.undofile = vim.o.undofile

        local undo_dir = vim.fs.joinpath(config_dir, "undo")
        ensure_dir(undo_dir)

        vim.opt.undodir = undo_dir
        vim.opt.undofile = true
    end

    -- === Session Support ===
    if flags.session then
        local session_path = vim.fs.joinpath(config_dir, "session.vim")

        if filetools.file_exists(session_path) then
            vim.cmd("silent! source " .. vim.fn.fnameescape(session_path))
        end
    end

    -- === Refresh buffers ===
    if flags.shada or flags.undo then
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if uitools.is_regular_buffer(bufnr) then
                if vim.api.nvim_buf_is_loaded(bufnr) and not vim.bo[bufnr].modified then
                    vim.api.nvim_buf_call(bufnr, function()
                        vim.cmd("silent! edit")
                    end)
                end
            end
        end
    end
end

function M.close()
    if not _state or not _originals then
        return
    end

    -- === Save Session with completely safe options ===
    if _state.flags.session then
        local session_path = vim.fs.joinpath(_state.config_dir, "session.vim")

        -- Temporarily set safe sessionoptions
        local old_sessionoptions = vim.o.sessionoptions
        vim.o.sessionoptions = SAFE_SESSIONOPTIONS

        vim.cmd("mksession! " .. vim.fn.fnameescape(session_path))

        -- Restore user's original sessionoptions
        vim.o.sessionoptions = old_sessionoptions
    end

    -- === Save ShaDa ===
    if _state.flags.shada then
        vim.cmd("wshada!")
    end

    -- === Restore Original Settings ===
    if _originals.shadafile ~= nil then
        vim.opt.shadafile = _originals.shadafile
    elseif _state.flags.shada then
        vim.opt.shadafile = ""
    end

    if _originals.undodir ~= nil then
        vim.opt.undodir = _originals.undodir
    end

    if _originals.undofile ~= nil then
        vim.opt.undofile = _originals.undofile
    end

    -- === Reload Global ShaDa ===
    if _state.flags.shada then
        vim.cmd("rshada!")
    end

    _state = nil
    _originals = nil
end

return M
