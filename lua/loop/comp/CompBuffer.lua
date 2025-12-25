local class = require('loop.tools.class')
local throttle = require('loop.tools.throttle')
local Trackers = require('loop.tools.Trackers')


---@alias loop.comp.Keymaps table<string,loop.KeyMap>

---@class loop.comp.Tracker
---@field on_change fun()|nil
---@field on_ui_flags_update fun()|nil

---@class loop.comp.CompBuffer
---@field new fun(self: loop.comp.CompBuffer, type : string, name:string): loop.comp.CompBuffer
---@field _renderer loop.CompRenderer|nil
local CompBuffer = class()

---@param type string
---@param name string
function CompBuffer:init(type, name)
    self._type = type
    self._name = name
    self._keymaps = {}
    self._buf = -1
    self._ui_flags = ""
    self._trackers = Trackers:new()
    self._no_change_events = false

    self._throttled_ui_flags_notification = throttle.throttle_wrap(100, function()
        self._trackers:invoke("on_ui_flags_update")
    end)

    self._throttled_render = throttle.throttle_wrap(100, function()
        self:_immediate_render()
    end)
end

---@return loop.BufferController
function CompBuffer:make_controller()
    ---@type loop.BufferController
    return {
        set_renderer = function(renderer)
            self:set_renderer(renderer)
        end,
        request_refresh = function()
            self:render()
        end,
        set_user_data = function(user_data)
            self:set_user_data(user_data)
        end,
        get_user_data = function()
            return self:get_user_data()
        end,
        set_ui_flags = function(flags)
            self:set_ui_flags(flags)
        end,
        add_keymap = function(key, keymap)
            self:add_keymap(key, keymap)
        end,
        get_cursor = function()
            return self:get_cursor()
        end,
        follow_last_line = function()
            self:follow_last_line()
        end,
        disable_change_events = function ()
            self:disable_change_events()
        end
    }
end

function CompBuffer:destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    if self._buf > 0 then
        vim.api.nvim_buf_delete(self._buf, { force = true })
        assert(self._buf == -1)
    end
    if self._renderer and self._renderer.dispose then
        self._renderer.dispose()
    end
end

---@param renderer loop.CompRenderer
function CompBuffer:set_renderer(renderer)
    self._renderer = renderer
end

function CompBuffer:set_user_data(data)
    self._user_data = data
end

function CompBuffer:get_user_data()
    return self._user_data
end

---@param callbacks loop.comp.Tracker>
---@return number
function CompBuffer:add_tracker(callbacks)
    return self._trackers:add_tracker(callbacks)
end

---@param id number
---@return boolean
function CompBuffer:remove_tracker(id)
    return CompBuffer._trackers:remove_tracker(id)
end

function CompBuffer:disable_change_events()
    self._no_change_events = true
end

function CompBuffer:follow_last_line()
    self._follow = true
end

function CompBuffer:_on_buf_enter()
    self:_apply_keymaps()
    if self._follow then
        local last_line = vim.api.nvim_buf_line_count(self._buf)
        vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
end

function CompBuffer:_on_buf_leave()
    if self._follow then
        local last_line = vim.api.nvim_buf_line_count(self._buf)
        vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
end

---@return string|nil
function CompBuffer:get_name()
    return self._name
end

---@return number -- buffer number
function CompBuffer:get_buf()
    if self._destroyed then
        return -1
    end
    return self._buf
end

---@return number -- buffer number
function CompBuffer:get_or_create_buf()
    assert(not self._destroyed)
    if self._buf ~= -1 then
        if not vim.api.nvim_buf_is_loaded(self._buf) then
            vim.fn.bufload(self._buf)
            self:_setup_buf(true)
            if self._renderer then
                self._renderer.render(self._buf)
            end
        end
        return self._buf
    end

    self._buf = vim.api.nvim_create_buf(false, true)
    self:_setup_buf(true)
    if self._renderer then
        self._renderer.render(self._buf)
    end
    return self._buf
end

---@param own_buf boolean
function CompBuffer:_setup_buf(own_buf)
    assert(self._buf > 0)
    local buf = self._buf

    local bufname = "loop://" .. self._name
    if vim.fn.bufexists(bufname) == 1 then
        bufname = "loop://" .. tostring(buf) .. '/' .. self._name
    end
    if vim.fn.bufexists(bufname) == 1 then
        ---@diagnostic disable-next-line: undefined-field
        local timestamp = ("%d"):format(vim.uv.hrtime())
        bufname = "loop://" .. tostring(buf) .. timestamp .. '/' .. self._name
    end

    vim.api.nvim_buf_set_name(buf, bufname)

    do
        local b = vim.bo[buf]
        if own_buf then
            b.buftype = "nofile"
            b.modifiable = false
        end
        b.bufhidden = "hide"
        b.swapfile = false
        b.undolevels = -1   -- buffer can't become "modified"
        b.buflisted = false -- hide from :ls
        b.filetype = "loop-" .. self._type
    end

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = buf,
        once = true,
        callback = function(ev)
            assert(ev.buf == buf)
            self._buf = -1
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
        callback = function(ev)
            assert(ev.buf == buf)
            self:_on_buf_enter()
        end
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function(ev)
            assert(ev.buf == buf)
            self:_on_buf_leave()
        end
    })
end

---@param key string
---@param keymap loop.KeyMap
function CompBuffer:add_keymap(key, keymap)
    assert(not self._keymaps[key])
    self._keymaps[key] = keymap
    self:_apply_keymap(key, keymap)
end

---@param keymaps table<string, loop.KeyMap>
function CompBuffer:add_keymaps(keymaps)
    for key, keymap in pairs(keymaps) do
        assert(not self._keymaps[key])
        self._keymaps[key] = keymap
        self:_apply_keymap(key, keymap)
    end
end

function CompBuffer:_apply_keymaps()
    if self._keymaps then
        for key, item in pairs(self._keymaps) do
            self:_apply_keymap(key, item)
        end
    end
end

---@param key string
---@param item loop.KeyMap
function CompBuffer:_apply_keymap(key, item)
    if self._buf ~= -1 then
        local modes = { "n" }
        --local ok =
        pcall(function() vim.keymap.del(modes, key, { buffer = self._buf }) end)
        vim.keymap.set(modes, key, function() item.callback() end, { buffer = self._buf, desc = item.desc })
    end
end

---@return integer[]|nil
function CompBuffer:get_cursor()
    if vim.api.nvim_get_current_buf() ~= self._buf then
        return nil
    end
    return vim.api.nvim_win_get_cursor(0)
end

---@return string
function CompBuffer:get_ui_flags()
    return self._ui_flags
end

---@param str string
function CompBuffer:set_ui_flags(str)
    self._ui_flags = str
    self._throttled_ui_flags_notification()
end

function CompBuffer:render()
    self._throttled_render()
end

function CompBuffer:_immediate_render()
    if not self._buf or self._buf <= 0 then return end
    if not self._renderer then return end

    local changed = self._renderer.render(self._buf, self._user_data)
    if changed and not self._no_change_events then
        self._trackers:invoke("on_change")
    end
end

return CompBuffer
