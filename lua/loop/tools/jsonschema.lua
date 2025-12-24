-- loop/tools/validator.lua
local M = {}

-- Helper: join JSON-pointer path
local function join_path(base, key)
    if base == "/" or base == "" then
        return base .. key
    end
    return base .. "/" .. key
end

---@param  errors string[]
---@param path string
---@param msg string
local function add_error(errors, path, msg)
    table.insert(errors, path .. ": " .. msg)
end

-- Helper: check enum
local function check_enum(enum_tbl, value)
    for _, v in ipairs(enum_tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- Core recursive validator
---@param schema table
---@param data any
---@param path string
---@return string[]?
local function validate(schema, data, path)
    ---@type string[]
    local errors = {}

    -- Type check — supports type as string or array (e.g. ["string", "null"])
    local allowed_types = type(schema.type) == "table" and schema.type or { schema.type }
    if allowed_types and not vim.tbl_isempty(allowed_types) then
        local ok = false
        for _, t in ipairs(allowed_types) do
            if t == "null" and data == nil then
                ok = true
                break
            elseif t == "object" and type(data) == "table" and not vim.islist(data) then
                ok = true
                break
            elseif t == "array" and vim.islist(data) then
                ok = true
                break
            elseif t == "string" and type(data) == "string" then
                ok = true
                break
            elseif t == "number" and type(data) == "number" then
                ok = true
                break
            elseif t == "boolean" and type(data) == "boolean" then
                ok = true
                break
            end
        end
        if not ok then
            local expected = table.concat(allowed_types, " or ")
            ---@type string
            local got = type(data)
            if got == "table" then
                got = vim.islist(data) and "array" or "object"
            elseif data == nil then
                got = "null"
            end
            add_error(errors, path, ("expected %s, got %s"):format(expected, got))
            return errors
        end
    end

    -- enum check
    if schema.enum then
        if not check_enum(schema.enum, data) then
            add_error(errors, path, "value not in enum: " .. table.concat(schema.enum, ", "))
            return errors
        end
    end

    --  const check
    if schema.const ~= nil then
        local function deep_equal(a, b)
            if a == b then return true end
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return false end

            for k, v in pairs(a) do
                if not deep_equal(v, b[k]) then return false end
            end
            for k, v in pairs(b) do
                if not deep_equal(v, a[k]) then return false end
            end
            return true
        end

        if not deep_equal(data, schema.const) then
            local expected = vim.inspect(schema.const)
            local got = vim.inspect(data)
            add_error(errors, path, ("value must be exactly %s, got %s"):format(expected, got))
            return errors
        end
    end

    -- 4. Object handling
    if schema.type == "object" or (type(schema.type) == "table" and vim.tbl_contains(schema.type, "object")) then
        if type(data) ~= "table" or vim.islist(data) then
            add_error(errors, path, "expected object, got " .. type(data))
            return errors
        end

        local props = schema.properties or {}
        local required = schema.required or {}

        -- Required fields
        for _, key in ipairs(required) do
            if data[key] == nil then
                add_error(errors, join_path(path, key), "required property missing")
            end
        end

        -- Validate known properties
        for key, subschema in pairs(props) do
            if data[key] ~= nil then
                local sub_err = validate(subschema, data[key], join_path(path, key))
                if sub_err then
                    vim.list_extend(errors, sub_err)
                end
            end
        end

        -- Handle additionalProperties
        local addl = schema.additionalProperties
        if addl == false then
            for key in pairs(data) do
                if not props[key] then
                    local valid = table.concat(vim.tbl_keys(props), ", ")
                    add_error(errors, join_path(path, key),
                        "invalid property, allowed: " .. (valid ~= "" and valid or "(none)"))
                end
            end
        elseif addl and type(addl) == "table" then
            for key, value in pairs(data) do
                if not props[key] then
                    local sub_err = validate(addl, value, join_path(path, key))
                    if sub_err then
                        vim.list_extend(errors, sub_err)
                    end
                end
            end
        end
    end

    -- . Array handling
    if schema.type == "array" or (type(schema.type) == "table" and vim.tbl_contains(schema.type, "array")) then
        if not vim.islist(data) then
            add_error(errors, path, "expected array")
            return errors
        end
        if schema.items then
            for i, value in ipairs(data) do
                local sub_err = validate(schema.items, value, path .. "/" .. i)
                if sub_err then
                    vim.list_extend(errors, sub_err)
                end
            end
        end
    end

    -- String pattern
    if (schema.type == "string" or (type(schema.type) == "table" and vim.tbl_contains(schema.type, "string"))) then
        if schema.pattern and type(data) == "string" then
            if not data:match(schema.pattern) then
                add_error(errors, path, ("string does not match pattern %q"):format(schema.pattern))
            end
        end
    end

    -- oneOf — first match wins
    if schema.oneOf then
        local matched = false
        local details = {}
        for i, sub in ipairs(schema.oneOf) do
            local sub_err = validate(sub, data, path)
            if not sub_err or #sub_err == 0 then
                matched = true
                break
            else
                table.insert(details, ("option %d: %s"):format(i, table.concat(sub_err, "; ")))
            end
        end
        if not matched then
            add_error(errors, path, "no schema in oneOf matched. Details:\n" .. table.concat(details, "\n"))
        end
    end

    -- Success: no errors
    if #errors == 0 then
        return nil
    end
    return errors
end

-- Public entry point
---@param schema table
---@param data any
---@return string[]?
function M.validate(schema, data)
    local errors = validate(schema, data, "")
    if not errors then
        return nil -- success
    end

    return errors
end

return M
