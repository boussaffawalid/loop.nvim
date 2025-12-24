local M = {}

---@param path string
function M.file_exists(path)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(path)
    return stat and stat.type == "file"
end

---@param path string
function M.dir_exists(path)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(path)
    return stat and stat.type == "directory"
end

---@param path string
---@return boolean
---@return string|nil
function M.make_dir(path)
    vim.fn.mkdir(path, "p")
    if not vim.fn.isdirectory(path) then
        local errmsg = vim.v.errmsg or ""
        return false, "Failed to create directory: " .. errmsg
    end
    return true
end

---@param filepath string
---@param data string
---@return boolean
---@return string | nil
function M.write_content(filepath, data)
    local fd = io.open(filepath, "w")
    if not fd then
        return false, "Cannot open file for write '" .. filepath or "" .. "'"
    end
    local ok, ret_or_err = pcall(function() fd:write(data) end)
    fd:close()
    return ok, ret_or_err
end

---@param filepath  string
---@return boolean success
---@return string content or error
function M.read_content(filepath)
    local fd = io.open(filepath, "r")
    if not fd then
        return false, "Cannot open file for read '" .. (filepath or "") .. "'"
    end
    local read_ok, content_or_err = pcall(function() return fd:read("*a") end)
    fd:close()
    if not content_or_err then
        return false, "failed to read from file '" .. (filepath or "") .. "'"
    end
    return read_ok, content_or_err
end

return M
