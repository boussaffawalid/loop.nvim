local M = {}

---@class loop.ws.WorkspaceInfo
---@field name string
---@field root_dir string
---@field config_dir string


---@type loop.ws.WorkspaceInfo?
local _info = nil

---@param info loop.ws.WorkspaceInfo?
function M.set_ws_info(info)
    _info = info
end

---@return string|nil
function M.get_ws_dir() return _info and _info.root_dir or nil end

---@return string
function M.status_line_comp()
    return (_info and _info.name) and ("󱂬 " .. _info.name) or ""
end

return M
