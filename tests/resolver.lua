require("plenary.busted")

local M = require("loop.tools.resolver")
local config = require("loop.config")

describe("loop.tools.resolver (variadic args)", function()
    --- Helper to wrap async resolve into a sync call for testing
    ---@param input any
    ---@return boolean ok, any val, string|nil err
    local function resolve(input)
        local done = false
        local res_ok, res_val, res_err

        M.resolve_macros(input, function(success, result, err)
            res_ok, res_val, res_err = success, result, err
            done = true
        end)

        vim.wait(2000, function() return done end, 10)

        if not done then error("Resolver timed out after 2s") end
        return res_ok, res_val, res_err
    end

    before_each(function()
        config.current.macros = {}
    end)

    it("supports an arbitrary number of arguments", function()
        config.current.macros.join = function(...)
            return table.concat({ ... }, "-")
        end

        local ok, res = resolve("${join:a,b,c}")
        assert.is_true(ok)
        assert.is_equal("a-b-c", res)
    end)

    it("handles nested macros with inner-to-outer resolution", function()
        config.current.macros.inner = function()
            return "foo"
        end

        config.current.macros.outer = function(arg)
            return "result_" .. arg
        end

        local ok, res = resolve("${outer:${inner}}")
        assert.is_true(ok)
        assert.is_equal("result_foo", res)
    end)

    it("respects escape sequences for colons and commas", function()
        config.current.macros.echo = function(arg)
            return arg
        end

        local ok1, res1 = resolve("${echo:key\\:value}")
        assert.is_equal("key:value", res1)

        local ok2, res2 = resolve("${echo:one\\,two}")
        assert.is_equal("one,two", res2)
    end)

    it("handles complex nesting: macros inside argument lists", function()
        config.current.macros.add = function(a, b)
            return tonumber(a) + tonumber(b)
        end

        config.current.macros.val = function()
            return "5"
        end

        local ok, res = resolve("${add:${val},5}")
        assert.is_true(ok)
        assert.is_equal("10", res)
    end)

    it("successfully escapes closing braces inside arguments", function()
        config.current.macros.wrap = function(arg)
            return "[" .. arg .. "]"
        end

        local ok, res = resolve("${wrap:content\\}here}")
        assert.is_true(ok)
        assert.is_equal("[content}here]", res)
    end)

    it("reports errors for unterminated macros", function()
        local ok, res, err = resolve("hello ${unclosed:arg")

        assert.is_false(ok)
        assert.truthy(err:find("Unterminated"))
    end)

    it("handles deeply nested tables and strings correctly", function()
        config.current.macros.get_env = function(key)
            local envs = { user = "ghost", home = "/home/ghost" }
            return envs[key]
        end

        local input = {
            config = {
                path = "${get_env:home}/.config",
                owner = "${get_env:user}"
            }
        }

        local ok, res = resolve(input)
        assert.is_true(ok)
        assert.are.same({
            config = {
                path = "/home/ghost/.config",
                owner = "ghost"
            }
        }, res)
    end)

    it("handles literal dollars via $$", function()
        config.current.macros.echo = function(arg)
            return arg
        end

        local ok, res = resolve("$$100 and ${echo:money}")
        assert.is_true(ok)
        assert.is_equal("$100 and money", res)
    end)

    it("handles macros that return errors via (nil, err)", function()
        config.current.macros.bad = function()
            return nil, "api offline"
        end

        local ok, res, err = resolve("status: ${bad}")
        assert.is_false(ok)
        assert.is_equal("api offline", err)
    end)

    it("handles the 'Large List' of edge cases", function()
        config.current.macros = {
            echo       = function(arg) return arg end,
            prefix     = function() return "real_macro" end,
            real_macro = function(arg) return "works_" .. arg end,
            upper      = function(arg) return string.upper(arg) end,
            count      = function(...) return select("#", ...) end,
        }

        local cases = {
            { input = "${${prefix}:success}",   expected = "works_success" },
            { input = "${echo:one\\,two}",      expected = "one,two" },
            { input = "${upper:${echo:hi}}",    expected = "HI" },
            { input = "Cost: $$${count:a,b,c}", expected = "Cost: $3" },
            { input = "${echo:  spaces  }",     expected = "  spaces  " },
        }

        for _, case in ipairs(cases) do
            local ok, res, err = resolve(case.input)
            assert.is_true(ok, "Failed on: " .. case.input .. " Error: " .. tostring(err))
            assert.is_equal(case.expected, res)
        end
    end)

    it("handles mixed content and adjacent macros", function()
        config.current.macros = {
            host = function() return "localhost" end,
            port = function() return "8080" end,
            user = function() return "root" end,
            ext  = function(ext) return ext or "txt" end,
        }

        local cases = {
            {
                input = "ssh://${user}@${host}:${port}",
                expected = "ssh://root@localhost:8080",
            },
            {
                input = "archive.${ext:tar}.${ext:gz}",
                expected = "archive.tar.gz",
            },
            {
                input = "Total: $$${port}",
                expected = "Total: $8080",
            },
            {
                input = "---${user}---",
                expected = "---root---",
            }
        }

        for _, case in ipairs(cases) do
            local ok, res, err = resolve(case.input)
            assert.is_true(ok, err)
            assert.is_equal(case.expected, res)
        end
    end)

    it("handles various bad inputs and malformed syntax", function()
        config.current.macros = {
            crash = function() error("system explosion") end,
            fail  = function() return nil, "database offline" end,
        }

        local cases = {
            { input = "${}",                  expected_err = "Unknown macro: ''" },
            { input = "${  }",                expected_err = "Unknown macro: ''" },
            { input = "${:only_args}",        expected_err = "Unknown macro: ''" },
            { input = "text ${missing_brace", expected_err = "Unterminated macro" },
            { input = "${non_existent}",      expected_err = "Unknown macro: 'non_existent'" },
            { input = "${crash}",             expected_err = "system explosion" },
            { input = "${fail}",              expected_err = "database offline" },
        }

        for _, case in ipairs(cases) do
            local ok, res, err = resolve(case.input)
            assert.is_false(ok)
            assert.is_nil(res)
            assert.truthy(err and err:find(case.expected_err),
                string.format("Expected '%s', got '%s'", case.expected_err, err))
        end
    end)
end)
