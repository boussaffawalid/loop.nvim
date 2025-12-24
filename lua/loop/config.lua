---@class loop.Config.Window.Symbols
---@field change string
---@field success string
---@field failure string

---@class loop.Config.Window
---@field symbols loop.Config.Window.Symbols

---@class window loop.Config.Window
---@class loop.Config
---@field selector "builtin"|"telescope"|"snacks"
---@field window loop.Config.Window
---@field macros table<string,(fun(arg:any):any,string|nil)>

local M = {}

---@type loop.Config|nil
M.current = nil

return M
