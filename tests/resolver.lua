require("plenary.busted")

local M = require("loop.tools.resolver")
local config = require("loop.config")

describe("loop.tools.resolver", function()
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
        -- Args is now a table!
        config.current.macros.join = function(args)
            return table.concat(args, "-")
        end

        local ok, res = resolve("${join:a,b,c}")
        assert.is_true(ok)
        assert.is_equal("a-b-c", res)
    end)

    it("handles nested macros with inner-to-outer resolution", function()
        config.current.macros.inner = function() return "foo" end
        config.current.macros.outer = function(args) return "result_" .. args[1] end

        -- Evaluates ${inner} first, then passes "foo" to outer
        local ok, res = resolve("${outer:${inner}}")
        assert.is_true(ok)
        assert.is_equal("result_foo", res)
    end)

    it("respects escape sequences for colons and commas", function()
        config.current.macros.echo = function(args) return args[1] end

        -- Escaping the colon so it's not treated as a separator
        local ok1, res1 = resolve("${echo:key\\:value}")
        assert.is_equal("key:value", res1)

        -- Escaping the comma so it's not treated as multiple arguments
        local ok2, res2 = resolve("${echo:one\\,two}")
        assert.is_equal("one,two", res2)
    end)

    it("handles complex nesting: macros inside argument lists", function()
        config.current.macros.add = function(args)
            return tonumber(args[1]) + tonumber(args[2])
        end
        config.current.macros.val = function() return "5" end

        -- ${add:5,5}
        local ok, res = resolve("${add:${val},5}")
        assert.is_true(ok)
        assert.is_equal("10", res)
    end)

    it("successfully escapes closing braces inside arguments", function()
        config.current.macros.wrap = function(args) return "[" .. args[1] .. "]" end

        -- Literal } inside the macro
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
        config.current.macros.get_env = function(args)
            local envs = { user = "ghost", home = "/home/ghost" }
            return envs[args[1]]
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
        config.current.macros.echo = function(args) return args[1] end

        -- Should become "$100" and not attempt to expand "${100}"
        local ok, res = resolve("$$100 and ${echo:money}")
        assert.is_true(ok)
        assert.is_equal("$100 and money", res)
    end)

    it("handles macros that return errors via (nil, err)", function()
        config.current.macros.bad = function() return nil, "api offline" end

        local ok, res, err = resolve("status: ${bad}")
        assert.is_false(ok)
        assert.is_equal("api offline", err)
    end)

    it("handles the 'Large List' of edge cases", function()
        -- Setup complex mock macros
        config.current.macros = {
            echo       = function(args) return args[1] end,
            prefix     = function() return "real_macro" end,
            real_macro = function(args) return "works_" .. args[1] end,
            upper      = function(args) return string.upper(args[1]) end,
            count      = function(args) return #args end,
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
            ext  = function(args) return args[1] or "txt" end,
        }

        local cases = {
            {
                input = "ssh://${user}@${host}:${port}",
                expected = "ssh://root@localhost:8080",
                desc = "URL style with adjacent delimiters"
            },
            {
                input = "archive.${ext:tar}.${ext:gz}",
                expected = "archive.tar.gz",
                desc = "Adjacent macros with arguments"
            },
            {
                input = "Total: $$${port}",
                expected = "Total: $8080",
                desc = "Literal dollar followed by macro"
            },
            {
                input = "---${user}---",
                expected = "---root---",
                desc = "Hyphenated boundaries"
            }
        }

        for _, case in ipairs(cases) do
            local ok, res, err = resolve(case.input)
            assert.is_true(ok, "Failed: " .. case.desc .. " | Error: " .. tostring(err))
            assert.is_equal(case.expected, res)
        end
    end)
    it("handles various bad inputs and malformed syntax", function()
        -- Setup macros that fail in specific ways
        config.current.macros = {
            crash = function() error("system explosion") end,
            fail  = function() return nil, "database offline" end,
        }

        local cases = {
            {
                input = "${}",
                expected_err = "Unknown macro: ''",
                desc = "Empty macro name"
            },
            {
                input = "${  }",
                expected_err = "Unknown macro: ''",
                desc = "Whitespace-only macro name"
            },
            {
                input = "${:only_args}",
                expected_err = "Unknown macro: ''",
                desc = "Arguments with no name"
            },
            {
                input = "text ${missing_brace",
                expected_err = "Unterminated macro",
                desc = "Unclosed macro at EOF"
            },
            {
                input = "${non_existent}",
                expected_err = "Unknown macro: 'non_existent'",
                desc = "Reference to undefined macro"
            },
            {
                input = "${crash}",
                expected_err = "system explosion",
                desc = "Macro that throws a Lua error"
            },
            {
                input = "${fail}",
                expected_err = "database offline",
                desc = "Macro that returns nil and error message"
            }
        }

        for _, case in ipairs(cases) do
            local ok, res, err = resolve(case.input)

            assert.is_false(ok, "Should have failed: " .. case.desc)
            assert.is_nil(res)
            assert.truthy(err and err:find(case.expected_err),
                string.format("Expected error '%s' but got '%s'", case.expected_err, err))
        end
    end)
end)
