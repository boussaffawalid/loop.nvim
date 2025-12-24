require("plenary.busted")
local Scheduler = require("loop.tools.Scheduler")

describe("loop.tools.Scheduler", function()
    -- Synchronous mock
    local function sync_start_node(behavior_map)
        behavior_map = behavior_map or {}
        return function(id, on_exit)
            local config = behavior_map[id] or { succeed = true }
            local control = { terminate = function() end }
            on_exit(config.succeed ~= false, config.reason)
            return control
        end
    end

    -- Async mock using vim.schedule (reliable in tests)
    local function async_start_node(behavior_map)
        behavior_map = behavior_map or {}
        return function(id, on_exit)
            local config = behavior_map[id] or { succeed = true }
            local control = { terminate = function() end }
            vim.schedule(function()
                on_exit(config.succeed ~= false, config.reason)
            end)
            return control
        end
    end

    it("completes a single node synchronously and terminates immediately", function()
        local sched = Scheduler:new({ { id = "test" } }, sync_start_node())
        local called = false
        sched:start("test", function(ok, trigger)
            called = true
            assert.is_true(ok)
            assert.equals("node", trigger)
        end)
        assert.is_true(called)
        assert.is_true(sched:is_terminated())
    end)

    it("completes a single node asynchronously and eventually terminates", function()
        local sched = Scheduler:new({ { id = "test" } }, async_start_node())
        local called = false
        sched:start("test", function(ok)
            called = true
            assert.is_true(ok)
        end)
        assert.is_false(called)
        vim.wait(200)
        assert.is_true(called)
        assert.is_true(sched:is_terminated())
    end)

    it("reports leaf node failure correctly", function()
        local sched = Scheduler:new({ { id = "fail" } }, sync_start_node({ fail = { succeed = false, reason = "boom" } }))
        local called = false
        sched:start("fail", function(ok, trigger, param)
            called = true
            assert.is_false(ok)
            assert.equals("node", trigger)
            assert.equals("boom", param)
        end)
        assert.is_true(called)
        assert.is_true(sched:is_terminated())
    end)

    it("reports failure when start_node cannot start a node", function()
        local start_node = function() return nil, "blocked" end
        local sched = Scheduler:new({ { id = "test" } }, start_node)
        local called = false
        sched:start("test", function(ok, trigger, param)
            called = true
            assert.is_false(ok)
            assert.equals("node", trigger)
            assert.equals("blocked", param)
        end)
        assert.is_true(called)
        assert.is_true(sched:is_terminated())
    end)

    it("detects invalid root node (not in graph)", function()
        local sched = Scheduler:new({ { id = "valid" } }, sync_start_node())
        local called = false
        sched:start("invalid", function(ok, trigger, param)
            called = true
            assert.is_false(ok)
            assert.equals("invalid_node", trigger)
            assert.equals("invalid", param)
        end)
        assert.is_true(called)
        assert.is_true(sched:is_terminated()) -- Should be true: early failure, no pending
    end)

    it("detects cycles in the graph", function()
        local nodes = {
            { id = "a",    deps = { "b" } },
            { id = "b",    deps = { "a" } },
            { id = "root", deps = { "a" } },
        }
        local sched = Scheduler:new(nodes, sync_start_node())
        local called = false
        sched:start("root", function(ok, trigger, param)
            called = true
            assert.is_false(ok)
            assert.equals("cycle", trigger)
        end)
        assert.is_true(called)
        assert.is_true(sched:is_terminated())
    end)

    it("executes sequential dependencies in order", function()
        local order = {}
        local start_node = function(id, on_exit)
            table.insert(order, "start:" .. id)
            local control = { terminate = function() end }
            vim.schedule(function()
                table.insert(order, "end:" .. id)
                on_exit(true, nil)
            end)
            return control
        end

        local nodes = {
            { id = "a" },
            { id = "b" },
            { id = "root", deps = { "a", "b" }, order = "sequence" },
        }

        local sched = Scheduler:new(nodes, start_node)

        local root_ok = false
        sched:start("root", function(ok)
            root_ok = ok
        end)

        vim.wait(300)

        assert.is_true(root_ok)
        assert.are.same({
            "start:a", "end:a",
            "start:b", "end:b",
            "start:root", "end:root",
        }, order)
        assert.is_true(sched:is_terminated())
    end)

    it("interrupts on terminate() and reports interrupt", function()
        local started = false
        local terminated = false

        local start_node = function(id, on_exit)
            started = true
            local control = {
                terminate = function()
                    terminated = true
                    -- Immediately report interruption from terminate() to prevent natural completion
                    on_exit(false, "interrupted by terminate")
                end
            }
            -- Schedule natural completion far in the future
            vim.schedule(function()
                vim.defer_fn(function()
                    if not terminated then
                        on_exit(true, nil)
                    end
                end, 1000)
            end)
            return control
        end

        local sched = Scheduler:new({ { id = "task" } }, start_node)

        local called = false
        local received_ok = nil
        local received_trigger = nil
        local received_param = nil

        sched:start("task", function(ok, trigger, param)
            called = true
            received_ok = ok
            received_trigger = trigger
            received_param = param
        end)

        vim.wait(50) -- let the task start
        assert.is_true(started)

        sched:terminate()

        vim.wait(200)

        assert.is_true(called)
        assert.is_false(received_ok)
        assert.equals("node", received_trigger) -- comes from leaf callback triggered by terminate()
        assert.equals("interrupted by terminate", received_param)
        assert.is_true(terminated)
        assert.is_true(sched:is_terminated())
    end)

    it("queues a new run after termination completes", function()
        local events = {}

        local start_node = function(id, on_exit)
            table.insert(events, "start:" .. id)
            local control = { terminate = function() end }
            vim.schedule(function()
                table.insert(events, "end:" .. id)
                on_exit(true, nil)
            end)
            return control
        end

        local sched = Scheduler:new({
            { id = "first" },
            { id = "second" },
        }, start_node)

        sched:start("first", function() end)

        vim.wait(50)
        sched:terminate()

        local second_called = false
        sched:start("second", function(ok)
            second_called = true
            assert.is_true(ok)
        end)

        vim.wait(300)

        assert.is_true(second_called)
        assert.is_true(sched:is_terminated())

        -- Use table.find or loop instead of vim.tbl_indexof (not available in minimal env)
        local function index_of(tbl, val)
            for i, v in ipairs(tbl) do
                if v == val then return i end
            end
        end

        local first_end = index_of(events, "end:first")
        local second_start = index_of(events, "start:second")
        assert.truthy(first_end, "first should end")
        assert.truthy(second_start, "second should start")
        assert.is_true(first_end < second_start)
    end)
end)
