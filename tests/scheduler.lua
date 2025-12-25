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
        sched:start("test", function(id, event) end, function(ok, trigger)
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
        sched:start("test", function(id, event) end, function(ok)
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
        sched:start("fail", function(id, event) end, function(ok, trigger, param)
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
        sched:start("test", function(id, event) end, function(ok, trigger, param)
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
        sched:start("invalid", function(id, event) end, function(ok, trigger, param)
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
        sched:start("root", function(id, event) end, function(ok, trigger, param)
            called = true
            assert.is_false(ok)
            assert.equals("cycle", trigger)
        end)
        vim.wait(100)
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
        sched:start("root", function(id, event) end, function(ok)
            root_ok = ok
        end)

        vim.wait(100)

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

        sched:start("task", function(id, event) end, function(ok, trigger, param)
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

        sched:start("first", function() end, function() end)

        vim.wait(50)
        sched:terminate()

        local second_called = false
        sched:start("second", function(id, event) end, function(ok)
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

    it("handles shared dependencies (diamond pattern) only once", function()
        local execution_count = 0
        local nodes = {
            { id = "shared" },
            { id = "a",     deps = { "shared" } },
            { id = "b",     deps = { "shared" } },
            { id = "root",  deps = { "a", "b" }, order = "parallel" },
        }

        local start_node = function(id, on_exit)
            if id == "shared" then execution_count = execution_count + 1 end
            vim.defer_fn(function() on_exit(true) end, 10)
            return { terminate = function() end }
        end

        local sched = Scheduler:new(nodes, start_node)
        local done = false

        sched:start("root", function() end, function(ok)
            done = true
            assert.is_true(ok)
        end)

        vim.wait(200, function() return done end)
        assert.equals(1, execution_count) -- Shared should not run twice
    end)

    it("respects sequential execution order", function()
        local log = {}
        local nodes = {
            { id = "step1" },
            { id = "step2" },
            { id = "root", deps = { "step1", "step2" }, order = "sequence" },
        }

        local start_node = function(id, on_exit)
            table.insert(log, id .. "_start")
            vim.defer_fn(function()
                table.insert(log, id .. "_stop")
                on_exit(true)
            end, 20)
            return { terminate = function() end }
        end

        local sched = Scheduler:new(nodes, start_node)
        local done = false
        sched:start("root", function() end, function() done = true end)

        vim.wait(500, function() return done end)

        -- In sequence, step1 must stop before step2 starts
        assert.equals("step1_start", log[1])
        assert.equals("step1_stop", log[2])
        assert.equals("step2_start", log[3])
        assert.equals("step2_stop", log[4])
    end)

    it("handles immediate start_node failures gracefully", function()
        local nodes = { { id = "fail_me" } }

        local start_node = function(id, on_exit)
            return nil, "OS Error: Permission Denied"
        end

        local sched = Scheduler:new(nodes, start_node)
        local result_ok, result_param
        local done = false

        sched:start("fail_me", function() end, function(ok, trigger, param)
            result_ok = ok
            result_param = param
            done = true
        end)

        vim.wait(100, function() return done end)
        assert.is_false(result_ok)
        assert.equals("OS Error: Permission Denied", result_param)
        assert.is_true(sched:is_terminated())
    end)

    it("terminates current run if start is called again", function()
        local terminated_ids = {}
        local nodes = { { id = "long_task" } }

        local start_node = function(id, on_exit)
            return { terminate = function() table.insert(terminated_ids, id) end }
        end

        local sched = Scheduler:new(nodes, start_node)

        -- Start run 1
        sched:start("long_task", function() end, function() end)
        assert.is_true(sched:is_running())

        -- Start run 2 immediately
        sched:start("long_task", function() end, function() end)

        -- Check if the first run's node was told to terminate
        assert.equals(1, #terminated_ids)
        assert.equals("long_task", terminated_ids[1])
    end)

    it("fires start and stop events in correct pairs", function()
        local nodes = {
            { id = "child" },
            { id = "root", deps = { "child" } }
        }
        local events = {}

        local start_node = function(id, on_exit)
            vim.defer_fn(function() on_exit(true) end, 5)
            return { terminate = function() end }
        end

        local sched = Scheduler:new(nodes, start_node)
        local done = false

        sched:start("root", function(id, event)
            table.insert(events, id .. ":" .. event)
        end, function() done = true end)

        vim.wait(200, function() return done end)

        -- Expected order: child starts/stops, then root starts/stops
        assert.equals("child:start", events[1])
        assert.equals("child:stop", events[2])
        assert.equals("root:start", events[3])
        assert.equals("root:stop", events[4])
    end)
end)
