local M = require("loop.tools.resolver")
local config = require("loop.config")

describe("loop.tools.resolver", function()
    -- Helper to wrap the async M.resolve_macros into a sync-like call for busted
    local function resolve(input)
        local done = false
        local res_ok, res_val, res_err

        M.resolve_macros(input, function(success, result, err)
            res_ok = success
            res_val = result
            res_err = err
            done = true
        end)

        vim.wait(2000, function() return done end, 10)
        
        if not done then error("Resolver timed out after 2s") end
        return res_ok, res_val, res_err
    end

    before_each(function()
        -- Clean slate for macros before every test
        config.current.macros = {}
    end)

    it("handles plain strings and tables with no macros", function()
        local input = { name = "static", data = { 1, 2, 3 } }
        local ok, res, err = resolve(input)
        
        assert.is_true(ok)
        assert.is_nil(err)
        assert.are.same(input, res)
    end)

    it("expands a basic macro", function()
        config.current.macros.user = function() return "Gemini" end

        local ok, res, err = resolve("hello ${user}")
        
        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_equal("hello Gemini", res)
    end)

    it("supports the new (val, err) return signature for macros", function()
        config.current.macros.fail = function() 
            return nil, "custom error message" 
        end

        local ok, res, err = resolve("trigger ${fail}")
        
        assert.is_false(ok)
        assert.is_equal("custom error message", err)
        assert.is_nil(res)
    end)

    it("handles macros that yield (like prompt/select)", function()
        -- We mock a yielding macro using a coroutine resume loop
        config.current.macros.async_val = function()
            local co = coroutine.running()
            vim.defer_fn(function()
                coroutine.resume(co, "async-result")
            end, 10)
            return coroutine.yield()
        end

        local ok, res, err = resolve("Value: ${async_val}")
        
        assert.is_true(ok)
        assert.is_equal("Value: async-result", res)
    end)

    it("handles literal dollars using $$", function()
        -- $$ should become $ and ${macro} should still expand
        config.current.macros.version = function() return "1.0" end
        
        local input = "Cost is $$100 for v${version}"
        local ok, res, err = resolve(input)
        
        assert.is_true(ok)
        assert.is_equal("Cost is $100 for v1.0", res)
    end)

    it("correctly parses complex arguments", function()
        config.current.macros.echo = function(arg) return arg end

        local ok, res, err = resolve("${echo:spaces and : colons}")
        
        assert.is_true(ok)
        assert.is_equal("spaces and : colons", res)
    end)

    it("expands macros recursively in nested tables", function()
        config.current.macros.ext = function() return "lua" end
        config.current.macros.dir = function() return "tests" end

        local input = {
            files = {
                { path = "${dir}/unit.${ext}" },
                { path = "${dir}/bench.${ext}" }
            }
        }

        local ok, res, err = resolve(input)
        
        assert.is_true(ok)
        assert.are.same({
            files = {
                { path = "tests/unit.lua" },
                { path = "tests/bench.lua" }
            }
        }, res)
    end)

    it("captures and reports pcall crashes in macros", function()
        config.current.macros.crash = function()
            error("total failure")
        end

        local ok, res, err = resolve("do ${crash}")
        
        assert.is_false(ok)
        assert.truthy(err:find("total failure"))
    end)

    it("handles multiple instances of the same macro in one string", function()
        local count = 0
        config.current.macros.inc = function()
            count = count + 1
            return count
        end

        -- Ensure each ${inc} is evaluated individually
        local ok, res, err = resolve("${inc} and ${inc}")
        
        assert.is_true(ok)
        assert.is_equal("1 and 2", res)
    end)

    it("converts boolean and number returns to strings inside templates", function()
        config.current.macros.bool = function() return true end
        config.current.macros.num = function() return 42 end

        local ok, res, err = resolve("Results: ${bool}, ${num}")
        
        assert.is_true(ok)
        assert.is_equal("Results: true, 42", res)
    end)
end)