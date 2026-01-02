local M = {}

local config = require('loop.config')

local unpack = unpack or table.unpack

--- Splits a string by a delimiter while respecting backslash escapes.
---@param str string
---@param sep string
---@return string[]
local function split_with_escapes(str, sep)
    local result = {}
    local current = ""
    local i = 1
    while i <= #str do
        local char = str:sub(i, i)
        if char == "\\" and i < #str then
            -- Escape next char: skip backslash, add next char literal
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
        
        if char == "\\" and i < #str then
            -- Keep the escape sequence intact for the inner parser
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
            local ret = vim.F.pack_len(pcall(fn, unpack(args)))
            coroutine.resume(parent_co, vim.F.unpack_len(ret))
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

        -- Handle literal $$ -> $
        if char == "$" and next_char == "$" then
            res = res .. "$"
            i = i + 2
        elseif char == "$" and next_char == "{" then
            local content, end_pos, parse_err = parse_nested(str, i + 1)
            if parse_err then return nil, parse_err end

            -- 1. Recursively expand the content (for nested macros)
            local expanded_inner, expand_err = expand_recursive(content)
            if expand_err then return nil, expand_err end

            -- 2. Parse Name and Arguments
            local macro_name, args_list = "", {}
            local colon_pos = expanded_inner:find(":")

            if colon_pos then
                macro_name = vim.trim(expanded_inner:sub(1, colon_pos - 1))
                local raw_args = expanded_inner:sub(colon_pos + 1)
                args_list = split_with_escapes(raw_args, ",")
            else
                macro_name = vim.trim(expanded_inner)
            end

            -- 3. Execute Macro
            local fn = config.current.macros[macro_name]
            if not fn then return nil, "Unknown macro: '" .. macro_name .. "'" end

            -- Receive: pcall_ok, val1, val2
            local status, val, macro_err = async_call(fn, args_list)

            -- Handle pcall crash (error thrown)
            if not status then 
                return nil, "Macro crashed: " .. tostring(val) 
            end

            -- Handle explicit error return (nil, "error")
            -- We check macro_err because val could be nil simply because void return
            if val == nil and macro_err then
                return nil, macro_err
            end

            res = res .. tostring(val or "")
            i = end_pos + 1
        else
            res = res .. char
            i = i + 1
        end
    end
    return res
end

--- Internal recursive walker for tables.
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
---@param val any The input to resolve.
---@param callback fun(success: boolean, result: any, err: string|nil)
function M.resolve_macros(val, callback)
    coroutine.wrap(function()
        local success, result, err

        -- Use xpcall to catch errors thrown by `error()` calls in macros or logic
        local call_ok, call_ret = xpcall(function()
            if type(val) == "table" then
                local tbl = vim.deepcopy(val)
                local ok, table_err = _expand_table(tbl, {})
                if not ok then error(table_err) end
                return tbl
            elseif type(val) == "string" then
                local res, expand_err = expand_recursive(val)
                if expand_err then error(expand_err) end
                return res
            else
                return val
            end
        end, debug.traceback)

        if call_ok then
            success = true
            result = call_ret
        else
            success = false
            -- Clean up stack trace if it matches the pattern, for cleaner logs/tests
            err = call_ret
            if type(err) == "string" then
               local clean = err:match(":%d+: (.*)\nstack traceback:")
               if clean then err = clean end
            end
        end

        vim.schedule(function()
            callback(success, result, err)
        end)
    end)()
end

return M