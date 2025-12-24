local M = {}

--- Pretty JSON encoder using only real Neovim built-ins
---@param obj any
---@param indent string|nil
---@return string
local function json_encode_pretty(obj, indent)
    indent = indent or "  "

    -- Neovim's JSON encoder (perfect escaping)
    local function encode_one(v)
        return vim.json.encode(v)
    end

    ---@param value string
    ---@param level number
    ---@param path string
    local function serialize(value, level, path)
        local indent_str  = indent:rep(level)
        local next_indent = indent:rep(level + 1)
        local t           = type(value)

        if t == "nil" or t == "number" or t == "boolean" or t == "string" then
            return encode_one(value)
        elseif t == "table" then
            if vim.islist(value) then
                -- ARRAY STYLE
                if #value == 0 then return "[]" end

                local parts = { "[" }
                for i = 1, #value do
                    table.insert(parts, "\n" .. next_indent .. serialize(value[i], level + 1, path .. '[]/'))
                    if i < #value then table.insert(parts, ",") end
                end
                table.insert(parts, "\n" .. indent_str .. "]")
                return table.concat(parts)
            else
                -- MAP STYLE
                local keys = {}
                for k in pairs(value) do
                    table.insert(keys, k)
                end
                if value.__order then
                    local ordered = value.__order
                    local index = 1
                    local priorities = {}
                    if ordered then
                        for _, v in ipairs(ordered) do
                            priorities[v] = index
                            index = index + 1
                        end
                    end
                    for _, v in ipairs(keys) do
                        if not priorities[v] then
                            priorities[v] = index
                            index = index + 1
                        end
                    end
                    --vim.notify(vim.inspect({path, priorities}))
                    table.sort(keys, function(a, b) return priorities[a] < priorities[b] end)
                else
                    table.sort(keys)
                end
                if #keys == 0 then return "{}" end
                local parts = { "{" }
                for _, k in ipairs(keys) do
                    if k ~= "__order" then
                        local key_json = type(k) == "string" and encode_one(k) or ('"' .. tostring(k) .. '"')
                        local val_json = serialize(value[k], level + 1, path .. k .. '/')
                        table.insert(parts, "\n" .. next_indent .. key_json .. ": " .. val_json .. ",")
                    end
                end
                -- Remove trailing comma
                parts[#parts] = parts[#parts]:gsub(",$", "")
                table.insert(parts, "\n" .. indent_str .. "}")
                return table.concat(parts)
            end
        else
            error("Unsupported type: " .. t)
        end
    end

    return serialize(obj, 0, "/")
end

---@param filepath string
---@param data any
---@return boolean
---@return string | nil
function M.save_to_file(filepath, data)
    local json = json_encode_pretty(data, nil)
    assert(type(json) == 'string')
    local fd = io.open(filepath, "w")
    if not fd then
        return false, "Cannot open file for write '" .. filepath or "" .. "'"
    end
    local ok, ret_or_err = pcall(function() fd:write(json) end)
    fd:close()
    return ok, ret_or_err
end

---@param filepath string
---@return boolean
---@return any | nil
function M.load_from_file(filepath)
    local fd = io.open(filepath, "r")
    if not fd then
        return false, "Cannot open file for read"
    end
    local read_ok, content = pcall(function() return fd:read("*a") end)
    fd:close()

    if not read_ok then
        return false, content
    end

    local decode_ok, data = pcall(vim.fn.json_decode, content)
    if not decode_ok or type(data) ~= "table" then
        return false, "failed to parse json " .. (type(data) == "string" and data or "")
    end
    return true, data
end

---@param content string
---@return boolean
---@return any | nil
function M.from_string(content)
    local decode_ok, data = pcall(vim.fn.json_decode, content)
    if not decode_ok or type(data) ~= "table" then
        return false, "failed to parse json " .. (type(data) == "string" and data or "")
    end
    return true, data
end

---@param data any
---@return string
function M.to_string(data)
    return json_encode_pretty(data, nil)
end

return M
