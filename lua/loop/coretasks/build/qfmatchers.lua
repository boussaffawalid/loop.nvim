local strtools = require("loop.tools.strtools")

---@class loop.task.QuickFixItem
---@field filename string
---@field lnum number
---@field col number
---@field text string|nil
---@field type string|nil

---@param line string
---@param context table
---@return loop.task.QuickFixItem|nil
local function _parse_gcc(line, context)
    -----------------------------------------------------------------
    -- GCC / Clang compile-time diagnostics
    -----------------------------------------------------------------
    local file, lnum, col, severity, message = line:match("^(.+):(%d+):(%d+):%s+([%a%s]+):%s+(.+)$")
    if file then
        local type = "E"
        if severity == "warning" then type = "W" end
        if severity == "note" then type = "I" end

        return {
            filename = file,
            lnum     = tonumber(lnum),
            col      = tonumber(col),
            text     = message,
            type     = type,
        }
    end
    -----------------------------------------------------------------
    -- GNU ld: file.o:(.text+0x25): undefined reference to `foo`
    -----------------------------------------------------------------
    local obj_file, msg = line:match("^(.+):%(%.[^%)]+%)[:%s]+(.+)$")
    if obj_file then
        return {
            filename = obj_file,
            lnum     = 1,
            col      = 1,
            text     = msg,
            type     = "E",
        }
    end
    -----------------------------------------------------------------
    -- Any line with "undefined reference to `symbol`"
    -----------------------------------------------------------------
    local sym = line:match("undefined reference to [`']([^'`']+)[`']")
    if sym then
        return {
            filename = "",
            lnum     = 1,
            col      = 1,
            text     = "undefined reference to `" .. sym .. "`",
            type     = "E",
        }
    end
    return nil
end


---@param line string The raw output line from luacheck
---@param context table Additional context
---@return loop.task.QuickFixItem|nil
local function _parse_luacheck(line, context)
    -- Match warning lines (indented with spaces/tabs, contain filename:line:col)
    local warning_pattern = "^%s*(.-):(%d+):(%d+):%s*(.+)$"
    local file, lnum, col, message = line:match(warning_pattern)

    if not (file and lnum and col and message) then
        return nil
    end

    -- Convert to numbers
    lnum = tonumber(lnum)
    col = tonumber(col)

    ---@type loop.task.QuickFixItem
    local item = {
        filename = file,
        lnum = lnum or 1,
        col = col or 1,
        text = message,
        type = "W", -- Warning
    }

    return item
end

---@type table<string,fun(line:string,context:table):loop.task.QuickFixItem>
return {
    gcc = _parse_gcc,
    luacheck = _parse_luacheck
}