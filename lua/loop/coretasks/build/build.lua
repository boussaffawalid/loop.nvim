local M = {}

local wsinfo = require('loop.wsinfo')

---@class loop.coretasks.build.Task : loop.Task
---@field command string[]|string|nil
---@field cwd string?
---@field env table<string,string>? # optional environment variables
---@field quickfix_matcher string|nil

---@param task loop.coretasks.build.Task
---@return function|nil
---@return string|nil
local function _make_output_parser(task)
    if not task.quickfix_matcher or task.quickfix_matcher == "" then
        return nil
    end

    local qfmatchers = require('loop.coretasks.build.qfmatchers')
    local quickfix_parser = qfmatchers[task.quickfix_matcher]
    if not quickfix_parser then
        return nil, "invalid quickfix matcher: " .. tostring(task.quickfix_matcher)
    end

    ---@param line string
    ---@return string
    local function normalize_string(line)
        --ansi color codes
        local pattern = "\27%[%d*;?%d*;?%d*[mGKHK]"
        line = line:gsub("\r\n?", "\n")
        line = line:gsub(pattern, "")
        return line
    end

    local first = true
    local parser_context = {}
    ---@type fun(stream: "stdout"|"stderr", lines: string[])
    return function(stream, lines)
        if first then
            vim.fn.setqflist({}, "r")
            first = false
        end
        local issues = {}
        for _, line in ipairs(lines) do
            local issue = quickfix_parser(normalize_string(line), parser_context)
            if issue then
                table.insert(issues, issue)
            end
        end
        if #issues > 0 then
            vim.fn.setqflist(issues, "a")
        end
    end
end

---@param task loop.coretasks.build.Task
---@param page_manager loop.PageManager
---@param on_exit loop.TaskExitHandler
---@return loop.TaskControl|nil
---@return string|nil
function M.start_build(task, page_manager, on_exit)
    if not task.command then
        return nil, "task.command is required"
    end

    local output_handler, matcher_error = _make_output_parser(task)
    if matcher_error then
        return nil, matcher_error
    end

    -- Your original args — unchanged, just using the resolved values
    ---@type loop.tools.TermProc.StartArgs
    local start_args = {
        name = task.name or "Unnamed Tool Task",
        command = task.command,
        env = task.env,
        cwd = task.cwd or wsinfo.get_ws_dir(),
        output_handler = output_handler,
        on_exit_handler = function(code)
            if code == 0 then
                on_exit(true, nil)
            else
                on_exit(false, "Exit code " .. tostring(code))
            end
        end,
    }

    local pagegroup = page_manager.get_page_group(task.type)
    if not pagegroup then
        pagegroup = page_manager.add_page_group(task.type, task.name)
    end
    if not pagegroup then
        return nil, "page manager expired"
    end

    local page_data, err_msg = pagegroup.add_page({
        id = "term",
        type = "term",
        buftype = "term",
        label = task.name,
        term_args = start_args,
        activate = true,
    })
    
    --add_term_page(task.name, start_args, true)
    local proc = page_data and page_data.term_proc or nil
    if not proc then
        return nil, err_msg
    end

    ---@type loop.TaskControl
    local controller = {
        terminate = function()
            proc:terminate()
        end
    }
    return controller, nil
end

return M
