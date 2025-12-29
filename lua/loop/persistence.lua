local M = {}

local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')

---@type {config_dir:string,flags:{shada:boolean, undo:boolean}} | nil
local _state = nil

---@type {shada:string?,shadafile:string|nil, undodir:string|nil, undofile:boolean|nil}?
local _originals = nil

local function ensure_dir(path)
    if vim.fn.isdirectory(path) == 0 then
        vim.fn.mkdir(path, "p")
    end
end

local function _refresh_buffers()
    -- === Refresh buffers ===
    -- This ensures buffers pick up the new undo/shada context
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if uitools.is_regular_buffer(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
            if not vim.bo[bufnr].modified then
                vim.api.nvim_buf_call(bufnr, function()
                    vim.cmd("silent! edit")
                end)
            end
        end
    end
end

function M.open(config_dir, flags)
    if not flags then return end

    ensure_dir(config_dir)

    if _state then M.close() end

    _state = { flags = flags, config_dir = config_dir }
    _originals = {}

    -- === ShaDa Support ===
    if flags.shada then
        local shada_path = vim.fs.joinpath(config_dir, "main.shada")
        vim.o.shadafile = shada_path
        if filetools.file_exists(shada_path) then
            vim.cmd("rshada!")
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

    if flags.shada or flags.undo then
        _refresh_buffers()
    end
end

function M.close()
    if not _state or not _originals then return end

    if vim.v.exiting ~= vim.NIL then
        return
    end

    -- === Close Undo ===
    if _state.flags.undo then
        vim.opt.undodir = _originals.undodir
        vim.opt.undofile = _originals.undofile
    end

    if _state.flags.shada or _state.flags.undo then
        _refresh_buffers()
    end

    _state = nil
    _originals = nil
end

return M
