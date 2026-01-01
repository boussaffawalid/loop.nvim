---@brief [[
--- This module handles recursive macro expansion with support for nesting,
--- escaping, and table walking.
---
--- Example: ${outer:${inner:arg}}
--- Escape Example: ${macro:value\:with\:colons}
---@brief ]]

local M = {}

local config = require('loop.config')

--- Splits a string by a delimiter while respecting backslash escapes.
---@param str string The string to split.
---@param sep string The separator character.
---@return string[]
local function split_with_escapes(str, sep)
    local result = {}
    local current = ""
    local i = 1
    while i <= #str do
        local char = str:sub(i, i)
        if char == "\\" then
            -- Peek next char
            local next_char = str:sub(i + 1, i + 1)
            current = current .. next_char
            i = i + 2
        elseif char == sep then
            table.insert(result, current)
            current = ""
            i = i + 1
        else
            current = current .. char
            i = i + 1
        end
    end
    table.insert(result, current)
    return result
end

--- Helper to find the end of a macro while respecting nesting and escapes.
---@param str string
---@param start_pos number
---@return string|nil content, number|nil end_pos, string|nil err
local function parse_nested(str, start_pos)
    local stack = 0
    local result = ""
    local i = start_pos

    while i <= #str do
        local char = str:sub(i, i)
        if char == "\\" then
            -- Preserve the escape sequence for the next recursive pass
            result = result .. char .. str:sub(i + 1, i + 1)
            i = i + 2
        elseif char == "{" then
            stack = stack + 1
            result = result .. char
            i = i + 1
        elseif char == "}" then
            stack = stack - 1
            if stack == 0 then return result:sub(2), i end
            result = result .. char
            i = i + 1
        else
            result = result .. char
            i = i + 1
        end
    end
    return nil, nil, "Unterminated macro"
end

local function async_call(fn, args)
    local parent_co = coroutine.running()
    vim.schedule(function()
        coroutine.wrap(function()
            local ok, ret1, ret2 = pcall(fn, unpack(args))
            coroutine.resume(parent_co, ok, ret1, ret2)
        end)()
    end)
    return coroutine.yield()
end

--- Recursive function to expand a string.
---@param str string
---@return string|nil result, string|nil err
local function expand_recursive(str)
    local res = ""
    local i = 1

    while i <= #str do
        local char = str:sub(i, i)
        local next_char = str:sub(i + 1, i + 1)

        if char == "$" and next_char == "$" then
            res = res .. "$"
            i = i + 2
        elseif char == "$" and next_char == "{" then
            local content, end_pos, parse_err = parse_nested(str, i + 1)
            if parse_err then return nil, parse_err end
            assert(content)

            -- 1. Recursively expand inner macros
            local expanded_inner, expand_err = expand_recursive(content)
            if expand_err then return nil, expand_err end
            assert(expanded_inner)

            -- 2. Extract Name and Multi-Args
            local macro_name, args_list = "", {}
            local colon_pos = expanded_inner:find(":")

            if colon_pos then
                macro_name = vim.trim(expanded_inner:sub(1, colon_pos - 1))
                local raw_args = expanded_inner:sub(colon_pos + 1)
                -- Split by comma, respecting \ ,
                args_list = split_with_escapes(raw_args, ",")
            else
                macro_name = vim.trim(expanded_inner)
            end

            -- 3. Execute Macro
            local fn = config.current.macros[macro_name]
            if not fn then return nil, "Unknown macro: '" .. macro_name .. "'" end

            local status, val, macro_err = async_call(fn, args_list)
            if not status then return nil, "Macro crashed: " .. tostring(val) end
            if val == nil then return nil, macro_err or "Macro failed" end

            res = res .. tostring(val)
            i = end_pos + 1
        else
            res = res .. char
            i = i + 1
        end
    end
    return res
end

-- ... _expand_table and resolve_macros remain the same as previous response ...
--- Internal recursive walker for tables.
---@param tbl table The table to process in-place.
---@param seen table<table, boolean> Memoization table to prevent infinite recursion on circular refs.
---@return boolean success
---@return string|nil err
local function _expand_table(tbl, seen)
    seen = seen or {}
    if seen[tbl] then return true end
    seen[tbl] = true

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local ok, err = _expand_table(v, seen)
            if not ok then return false, err end
        elseif type(v) == "string" then
            local res, err = expand_recursive(v)
            if err then return false, err end
            tbl[k] = res
        end
    end
    return true
end

--- Resolves all macros within a string or a table.
--- This function is yield-safe and runs inside a coroutine.
---@param val any The input to resolve (string, table, or other).
---@param callback fun(success: boolean, result: any, err: string|nil) The completion callback.
function M.resolve_macros(val, callback)
    coroutine.wrap(function()
        ---@type boolean, any, string|nil
        local success, result, err

        if type(val) == "table" then
            -- Use deepcopy to ensure atomicity (don't ruin original table if a macro fails)
            local tbl = vim.deepcopy(val)
            local ok, table_err = _expand_table(tbl, {})
            success, result, err = ok, (ok and tbl or nil), table_err
        elseif type(val) == "string" then
            local res, expand_err = expand_recursive(val)
            success, result, err = (expand_err == nil), res, expand_err
        else
            -- For numbers, booleans, etc.
            success, result = true, val
        end

        -- Return to the main loop before calling the user callback
        vim.schedule(function()
            callback(success, result, err)
        end)
    end)()
end

return M
