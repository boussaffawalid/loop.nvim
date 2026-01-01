--- @meta
error('Cannot require a meta file')

---@class loop.WorkspaceConfig
---@field name string
---@field save {include:string[], exclude:string[],follow_symlinks:boolean}

---@class loop.Task
---@field name string # non-empty task
---@field type "composite"|string # task type
---@field depends_on string[]? # optional list of dependent task names
---@field depends_order "sequence"|"parallel"|nil # default is sequence

---@class loop.taskTemplate
---@field name string
---@field task loop.Task

---@class loop.TaskControl
---@field terminate fun()

---@alias loop.TaskExitHandler fun(success:boolean,reason:string|nil)

---@class loop.TaskProviderStore
---@field get fun(key:string):any
---@field set fun(key:string, value:any)
---@field keys fun():string[]

---@class loop.Workspace
---@field name string
---@field root string

---@class loop.TaskProvider
---@field on_workspace_open? fun(ws:loop.Workspace, store:loop.TaskProviderStore)
---@field on_workspace_close? fun(ws:loop.Workspace)
---@field on_store_will_save? fun(ws:loop.Workspace, store:loop.TaskProviderStore)
---@field get_config_schema (fun():table)|nil
---@field get_config_template (fun():table)|nil
---@field get_task_schema fun():table
---@field get_task_templates fun(config:table|nil):loop.taskTemplate[]
---@field start_one_task fun(task:loop.Task,page_manager:loop.PageManager, on_exit:loop.TaskExitHandler):(loop.TaskControl|nil,string|nil)

---@class loop.KeyMap
---@field callback fun()
---@field desc string

---@class loop.CompRenderer
---@field render fun(bufnr:number):boolean -- return true if changed
---@field dispose fun()

---@class loop.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.BaseBufferController
---@field set_user_data fun(user_data:any)
---@field get_user_data fun():any
---@field add_keymap fun(key:string,keymap:loop.KeyMap)
---@field get_cursor fun():integer[]|nil
---@field disable_change_events fun()

---@class loop.OutputBufferController : loop.BaseBufferController
---@field add_lines fun(lines: string|string[], highlights:loop.Highlight[]?)
---@field set_auto_scroll fun(enabled: boolean)

---@class loop.CompBufferController : loop.BaseBufferController
---@field set_renderer fun(renderer:loop.CompRenderer)
---@field request_refresh fun()

---@alias loop.ReplCompletionHandler fun(input:string, callback:fun(suggestions:string[]?,err:string?))

---@class loop.ReplController
---@field set_input_handler fun(handler:fun(input:string))
---@field set_completion_handler fun(handler:loop.ReplCompletionHandler)?
---@field add_output fun(text:string)

---@class loop.PageController
---@field set_ui_flags fun(flags:string)

---@class loop.PageOpts
---@field type "term"|"output"|"comp"|"repl"
---@field id string
---@field buftype string
---@field label string
---@field activate boolean?
---@field term_args loop.tools.TermProc.StartArgs?

---@class loop.PageData
---@field page loop.PageController
---@field base_buf loop.BaseBufferController?
---@field output_buf loop.OutputBufferController?
---@field comp_buf loop.CompBufferController?
---@field repl_buf loop.ReplController?
---@field term_proc loop.tools.TermProc?

---@class loop.PageGroup
---@field add_page fun(opts:loop.PageOpts):loop.PageData?,string?
---@field get_page fun(id:string):loop.PageData|nil
---@field activate_page fun(id:string)
---@field delete_pages fun()

---@class loop.PageManager
---@field add_page_group fun(id:string,label:string):loop.PageGroup|nil
---@field get_page_group fun(id:string):loop.PageGroup|nil
---@field delete_page_group fun(id:string)
---@field delete_all_groups fun(expire:boolean)
---@field get_page fun(group_id:string,page_id:string):loop.PageData|nil

---@alias loop.PageManagerFactory fun():loop.PageManager
