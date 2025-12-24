local class = require('loop.tools.class')
local CompBuffer = require('loop.comp.CompBuffer')

---@class loop.pages.Page : loop.comp.CompBuffer
---@field new fun(self: loop.pages.Page, type : string, name:string): loop.pages.Page
---@field _renderer loop.CompRenderer|nil
local Page = class(CompBuffer)

local buffer_flag_key = "loopplugin_page_efc0bed4-145b"

function Page.is_page(buf)
    local have_var, _ = pcall(vim.api.nvim_buf_get_var, buf, buffer_flag_key)
    return have_var
end

---@param own_buf boolean
function Page:_setup_buf(own_buf)
    CompBuffer._setup_buf(self, own_buf)
    assert(self._buf > 0)
    local buf = self._buf
    vim.api.nvim_buf_set_var(buf, buffer_flag_key, 1)
end

return Page
