local M = {}

local jsontools = require('loop.tools.json')
local filetools = require('loop.tools.file')
local uitools = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')
local jsonschema = require('loop.tools.jsonschema')
local resolver = require('loop.tools.resolver')

---@param content string
---@param tasktype_to_schema table<string,Object>
---@return loop.Task[]|nil
---@return string[]|nil
local function _load_tasks_from_str(content, tasktype_to_schema)
    if content == "" then
        return {}, nil
    end
    local loaded, data_or_err = jsontools.from_string(content)
    if not loaded or type(data_or_err) ~= 'table' then
        return nil, { data_or_err }
    end

    local data = data_or_err
    do
        local schema = require("loop.task.tasksschema").base_schema
        local errors = jsonschema.validate(schema, data)
        if errors and #errors > 0 then
            return nil, errors
        end
        if not data or not data.tasks then
            return nil, { "Parsing error" }
        end
    end

    ---@type loop.Task[]
    local tasks = data.tasks
    for _, task in ipairs(tasks) do
        local schema = tasktype_to_schema[task.type]
        if not schema then
            return nil, { "Invalid task type: " .. task.type }
        end
        local errors = jsonschema.validate(schema, task)
        if errors and #errors > 0 then
            table.insert(errors, 1, "Failed to load task: " .. task.name)
            return nil, errors
        end
    end

    return data.tasks, nil
end

---@param filepath string
---@param tasktype_to_schema table<string,Object>
---@return loop.Task[]|nil
---@return string[]|nil
local function _load_tasks_file(filepath, tasktype_to_schema)
    local loaded, contents_or_err = uitools.smart_read_file(filepath)
    if not loaded then
        if not filetools.file_exists(filepath) then
            return {}, nil -- not an error
        end
        return nil, { contents_or_err }
    end
    return _load_tasks_from_str(contents_or_err, tasktype_to_schema)
end

---@param config_dir string
---@param new_task loop.Task
---@param tasks_file_schema Object
---@return boolean
---@return string[]|nil
function M.add_task(config_dir, new_task, tasks_file_schema)
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    local winid, bufnr = uitools.smart_open_file(filepath)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false, { "failed to open tasks file" }
    end

    -- Get all lines
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    local new_lines = nil
    if #content == 0 then
        local tasks = { new_task }
        local schema_filepath = vim.fs.joinpath(config_dir, 'tasksschema.json')
        jsontools.save_to_file(schema_filepath, tasks_file_schema)
        local file_data = {}
        file_data["$schema"] = './tasksschema.json'
        file_data["tasks"] = tasks
        local new_content = jsontools.to_string(file_data)
        new_lines = vim.split(new_content, "\n", { plain = true })
    else
        local task_as_json = jsontools.to_string(new_task)
        local positions = {}
        for i = 1, #content do
            if content:sub(i, i) == "}" then
                table.insert(positions, i)
            end
        end
        -- Need at least two braces
        if #positions >= 2 then
            -- Find position of second-to-last brace
            local insert_pos = positions[#positions - 1]
            -- Insert the new text right before it
            local prev_lines = vim.split(content:sub(1, insert_pos) .. ',', "\n", { plain = true })
            local mid_lines = vim.split(task_as_json, "\n", { plain = true, trimempty = true })
            local next_lines = vim.split(content:sub(insert_pos + 1), "\n", { plain = true, trimempty = true })
            for idx, line in ipairs(mid_lines) do
                mid_lines[idx] = "    " .. line
            end
            new_lines = vim.list_extend(vim.list_extend(prev_lines, mid_lines), next_lines)
        end
    end
    if new_lines then
        -- Replace all lines in the buffer
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
        if vim.api.nvim_get_current_buf() == bufnr then
            uitools.move_to_last_occurence(winid, '"name": "')
        end
    end
    return true
end

---@param config_dir string
function M.open_tasks_config(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    uitools.smart_open_file(filepath)
end

---@param config_dir string
---@param tasktype_to_schema table<string,Object>
---@return loop.Task[]|nil
---@return string[]|nil
function M.load_tasks(config_dir, tasktype_to_schema)
    local filepath = vim.fs.joinpath(config_dir, "tasks.json")
    local tasks, errors = _load_tasks_file(filepath, tasktype_to_schema)
    if not tasks then
        return nil, strtools.indent_errors(errors, "error(s) in: " .. filepath)
    end

    local byname = {}
    for _, task in ipairs(tasks) do
        if byname[task.name] ~= nil then
            return nil, { "error in: " .. filepath, "  duplicate task name: " .. task.name }
        end
        byname[task.name] = task
    end

    return tasks, nil
end

---@param name string
---@param config_dir string
function M.save_last_task_name(name, config_dir)
    local filepath = vim.fs.joinpath(config_dir, "last.json")
    local data = { task = name }
    jsontools.save_to_file(filepath, data)
end

---@param config_dir string
---@return string|nil
function M.load_last_task_name(config_dir)
    local filepath = vim.fs.joinpath(config_dir, "last.json")
    local ok, payload = jsontools.load_from_file(filepath)
    if not ok then
        return nil
    end
    return payload and payload.task or nil
end

---@param config_dir string
---@param name string
---@return table?
function M.load_provider_state(config_dir, name)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    local filepath = vim.fs.joinpath(config_dir, "state." .. name .. ".json")
    if not filetools.file_exists(filepath) then
        return nil
    end
    local decoded, data_or_err = jsontools.load_from_file(filepath)
    assert(decoded, "failed to load state file for " .. name)
    return data_or_err
end

---@param config_dir string
---@param name string
---@param state table
function M.save_provider_state(config_dir, name, state)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    assert(state)
    local filepath = vim.fs.joinpath(config_dir, "state." .. name .. ".json")
    jsontools.save_to_file(filepath, state)
end

---@param config_dir string
---@param name string
---@param config_schema table
---@param callback fun(config:table|nil,err:string[]|nil)
function M.load_provider_config(config_dir, name, config_schema, callback)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    assert(type(config_schema) == "table")

    local filepath = vim.fs.joinpath(config_dir, "task." .. name .. ".json")
    if not filetools.file_exists(filepath) then
        return callback(nil, { "Config file does not exist:", filepath }) -- not an error
    end

    local loaded, contents_or_err = uitools.smart_read_file(filepath)
    if not loaded then
        return callback(nil, { contents_or_err })
    end

    local decoded, data_or_err = jsontools.from_string(contents_or_err)
    if not decoded then
        return callback(nil, { data_or_err })
    end

    local data = data_or_err
    if not data then
        return callback(nil, { "Parsing error" })
    end

    local errors = jsonschema.validate(config_schema, data)
    if errors and #errors > 0 then
        return callback(nil, errors)
    end

    local cmake_config = data.config

    resolver.resolve_macros(cmake_config, function(success, result_table, err)
        if not success or not result_table then
            callback(nil, { err or "failed to resolve macros" })
        else
            callback(result_table, nil)
        end
    end)
end

---@param config_dir string
---@param name string
---@param schema table
---@param template table
function M.open_provider_config(config_dir, name, schema, template)
    assert(name and name:match("[_%a][_%w]*") ~= nil, "invalid input")
    assert(type(schema) == "table")
    assert(type(template) == "table")

    if next(template) == nil then
        -- task does not require configuration
        return
    end

    local config_filepath = vim.fs.joinpath(config_dir, 'task.' .. name .. '.json')

    if not filetools.file_exists(config_filepath) then
        local schemafilename = 'extschema.' .. name .. '.json'
        local schemafilepath = vim.fs.joinpath(config_dir, schemafilename)
        jsontools.save_to_file(schemafilepath, schema)
        template["$schema"] = './' .. schemafilename
        jsontools.save_to_file(config_filepath, template)
    end

    uitools.smart_open_file(config_filepath)
end

return M
