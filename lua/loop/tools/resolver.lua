local M = {}
local config = require('loop.config')

-- Unique marker to protect literal "$$"
local LITERAL_MARKER = "\027\027LITERAL\027\027"

---@param spec string
local function parse_macro_spec(spec)
    local name, args = spec:match("^([^:%s]-)%s*:(.*)$")
    if not name then
        name = spec:match("^([^:%s]-)%s*$")
    end
    return name, args
end

---@param str string
---@return boolean success, string|nil result, string|nil err
local function _expand_string(str)
    -- 1. Protect literal dollars. Wrap gsub in () to discard the match count.
    local working_str = (str:gsub("%$%$", LITERAL_MARKER))

    -- 2. Collect all macro tasks
    local tasks = {}
    for full_spec in working_str:gmatch("%${([^}]+)}") do
        local name, arg = parse_macro_spec(full_spec)
        table.insert(tasks, {
            full_spec = "${" .. full_spec .. "}",
            name = name,
            arg = arg,
            result = nil
        })
    end

    if #tasks == 0 then
        -- Force single value return for the string
        return true, str
    end

    -- 3. Execute macros (Yield-Safe loop)
    for _, task in ipairs(tasks) do
        local fn = config.current.macros[task.name]
        
        if not fn then
            return false, nil, "Unknown macro: " .. task.full_spec
        end

        -- Capture (status, value, error_msg)
        local status, val, macro_err = pcall(fn, task.arg)

        if not status then
            return false, nil, ("Macro %s crashed: %s"):format(task.name, tostring(val))
        end

        if val == nil then
            -- Macro returned nil, so the 2nd return is the error message
            return false, nil, macro_err or ("Macro %s failed"):format(task.name)
        end

        task.result = tostring(val)
    end

    -- 4. Replace in String
    local final_res = working_str
    for _, task in ipairs(tasks) do
        -- escapes every Lua pattern metacharacter by prefixing it with %
        local pattern = task.full_spec:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local replacement = task.result:gsub("%%", "%%%%")
        final_res = (final_res:gsub(pattern, replacement, 1))
    end

    -- 5. Restore literal dollars
    return true, (final_res:gsub(LITERAL_MARKER, "$"))
end

--- Recursive table walker
local function _expand_table(tbl, seen)
    seen = seen or {}
    if seen[tbl] then return true end
    seen[tbl] = true

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local ok, err = _expand_table(v, seen)
            if not ok then return false, err end
        elseif type(v) == "string" then
            local ok, res, err = _expand_string(v)
            if not ok then return false, err end
            tbl[k] = res
        end
    end
    return true
end

---@param val any String or Table
---@param callback fun(success:boolean, result:any, err:string|nil)
function M.resolve_macros(val, callback)
    coroutine.wrap(function()
        local success, result, err

        if type(val) == "table" then
            -- Use deepcopy to avoid mutating the input table if it fails halfway
            local tbl = vim.deepcopy(val)
            local ok, table_err = _expand_table(tbl)
            success, result, err = ok, (ok and tbl or nil), table_err
        elseif type(val) == "string" then
            success, result, err = _expand_string(val)
        else
            success, result = true, val
        end

        vim.schedule(function()
            callback(success, result, err)
        end)
    end)()
end

return M