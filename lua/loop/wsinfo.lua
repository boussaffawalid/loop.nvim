local M = {}

---@type string|nil
local _ws_dir = nil

---@type string
local _config_dir = nil

---@param wsdir string|nil
function M.set_ws_info(wsdir) 
    _ws_dir = wsdir 
end

---@return string|nil
function M.get_ws_dir() return _ws_dir end

function M.status_line_comp()
	local wsinfo = require('loop.wsinfo')
	local dir = wsinfo.get_ws_dir()
	if dir and dir ~= "" then
		-- Get the last part of the path (the folder name)
		local name = vim.fn.fnamemodify(dir, ":p:h:t") -- Add a workspace icon if you have a Nerd Font installed
		return "󱂬 " .. name
	end
	return ""
end


    

return M