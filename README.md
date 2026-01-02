# loop.nvim

<p align="center">
  <strong>Workspace and Task Management for Neovim.</strong>
</p>

<p align="center">
  <a href="https://neovim.io/">
    <img src="https://img.shields.io/badge/Neovim-0.10+-blueviolet.svg?style=flat-square&logo=neovim" alt="Neovim 0.10+">
  </a>
  <a href="https://github.com/mbfoss/loop.nvim/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="MIT License">
  </a>
</p>

---

> [!WARNING]
> **Work in Progress**: This plugin is in early development and not ready for public release yet.

## 📖 Introduction

**loop.nvim** is a powerful workspace and task management system for Neovim. It provides a structured way to define, organize, and execute complex build tasks, run applications, and manage project workflows directly from your editor.

Unlike simple terminal runners, `loop.nvim` introduces the concept of **Workspaces** - project-specific configurations stored in a `.nvimloop` directory that manage task definitions, UI layouts, and workspace state.

### ✨ Key Features

- **Workspace Management**: Automatically detects and loads project configurations from `.nvimloop` directories
- **Task Scheduling**: Run tasks with dependency resolution, parallel/sequential execution, and automatic task ordering
- **Multiple Task Types**: Built-in support for build tasks, run tasks, vim commands, and composite tasks
- **Quickfix Integration**: Automatic parsing of compiler output (GCC, Clang, luacheck) into Neovim's quickfix list
- **Macro System**: Powerful variable substitution using `${macro}` syntax for dynamic task configuration
- **UI Management**: Built-in window and page management for task outputs with visual progress tracking
- **Task Dependencies**: Define complex workflows with task dependencies and execution order
- **Auto-Save**: Automatically saves workspace state and task configurations
- **Lazy Loading**: Light initialization that only fully loads when needed

---

## ⚡ Requirements

- Neovim >= **0.10**

---

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "mbfoss/loop.nvim",
    cmd = { "Loop" }, -- Lazy load on the command
    config = function()
        require("loop").setup({
            -- Optional global configuration
        })
    end
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'mbfoss/loop.nvim',
    config = function()
        require('loop').setup()
    end
}
```

---

## ⚙️ Configuration

### Global Setup

You can customize the plugin behavior through the `setup()` function:

```lua
require("loop").setup({
    selector = "builtin", -- UI selector: "builtin", "telescope", or "snacks"
    persistence = {
        shada = false,    -- Enable shada persistence
        undo = false,     -- Enable undo persistence
    },
    window = {
        symbols = {
            change  = "●",  -- Task changed
            success = "✓",  -- Task succeeded
            failure = "✗",  -- Task failed
            waiting = "⧗",  -- Task waiting
            running = "▶",  -- Task running
        },
    },
    macros = {}, -- Custom macros (see Macros section)
})
```

### Workspace Configuration

When you create a workspace with `:Loop workspace create`, a `.nvimloop` directory is created in your project root containing:

- `workspace.json` - Workspace configuration (name, save patterns, etc.)
- `tasks.json` - Task definitions
- Provider-specific configuration files

The workspace automatically loads when you open Neovim in a directory containing `.nvimloop`.

---

## 🚀 Usage

The primary interaction is through the `:Loop` user command, which provides tab-completion for all subcommands.

### Workspace Commands

| Command | Description |
|---------|-------------|
| `:Loop workspace create` | Initialize a new workspace in the current directory |
| `:Loop workspace open` | Open the workspace from the current directory |
| `:Loop workspace info` | Display information about the current workspace |
| `:Loop workspace configure` | Open/edit the workspace configuration file |
| `:Loop workspace save` | Save workspace buffers (as defined in workspace config) |

### Task Commands

| Command | Description |
|---------|-------------|
| `:Loop task run [name]` | Run a specific task (opens selector if name omitted) |
| `:Loop task repeat` | Repeat the last executed task |
| `:Loop task add [type]` | Create a new task of the specified type |
| `:Loop task configure` | Open the tasks configuration file |
| `:Loop task configure [type]` | Configure a specific task provider |
| `:Loop task terminate` | Stop all currently running tasks |

### UI Commands

| Command | Description |
|---------|-------------|
| `:Loop toggle` | Toggle the Loop UI window visibility |
| `:Loop show` | Show the Loop UI window |
| `:Loop hide` | Hide the Loop UI window |
| `:Loop page switch` | Switch between active output pages |
| `:Loop page open [group] [page]` | Open a specific page in the current window |

---

## 📋 Task Types

### Build Tasks

Build tasks execute shell commands and can parse output into Neovim's quickfix list.

**Schema:**
```json
{
  "name": "Build",
  "type": "build",
  "command": "make",
  "cwd": "${wsdir}",
  "quickfix_matcher": "gcc",
  "env": {
    "VAR": "value"
  },
  "depends_on": []
}
```

**Properties:**
- `command` (string|array): Command to execute (shell command or array of args)
- `cwd` (string): Working directory (supports macros)
- `quickfix_matcher` (string): Parser for compiler output (`"gcc"` or `"luacheck"`)
- `env` (object): Optional environment variables
- `depends_on` (array): List of task names that must complete first

**Quickfix Matchers:**
- `gcc`: Parses GCC/Clang compiler output and linker errors
- `luacheck`: Parses luacheck linter output

**Example:**
```json
{
  "name": "Compile C++",
  "type": "build",
  "command": "g++ -g -std=c++23 ${file:cpp} -o ${fileroot}.out",
  "cwd": "${wsdir}",
  "quickfix_matcher": "gcc",
  "depends_on": []
}
```

### Run Tasks

Run tasks execute long-running applications (servers, watchers, etc.) without quickfix parsing.

**Schema:**
```json
{
  "name": "Run Server",
  "type": "run",
  "command": "python -m http.server 8000",
  "cwd": "${wsdir}",
  "env": {
    "PORT": "8000"
  },
  "depends_on": []
}
```

**Example:**
```json
{
  "name": "Start Dev Server",
  "type": "run",
  "command": "npm run dev",
  "cwd": "${wsdir}",
  "depends_on": ["install-deps"]
}
```

### Vim Command Tasks

Execute Neovim commands or Lua code as tasks.

**Schema:**
```json
{
  "name": "Format Buffer",
  "type": "vimcmd",
  "command": "lua vim.lsp.buf.format()",
  "depends_on": []
}
```

**Example:**
```json
{
  "name": "Run Tests",
  "type": "vimcmd",
  "command": "lua require('plenary.test_harness').test_directory('tests/')",
  "depends_on": []
}
```

### Composite Tasks

Combine multiple tasks with parallel or sequential execution.

**Schema:**
```json
{
  "name": "Full Workflow",
  "type": "composite",
  "depends_on": ["task1", "task2", "task3"],
  "depends_order": "parallel"  // or "sequence"
}
```

**Properties:**
- `depends_on` (array): List of task names to execute
- `depends_order` (string): `"parallel"` or `"sequence"`

**Example:**
```json
{
  "name": "Build and Test",
  "type": "composite",
  "depends_on": ["lint", "build", "test"],
  "depends_order": "sequence"
}
```

---

## 🔧 Macros

Macros allow dynamic variable substitution in task configurations using `${macro}` syntax.

### Built-in Macros

| Macro | Description | Example |
|-------|-------------|---------|
| `${wsdir}` | Workspace root directory | `/path/to/project` |
| `${cwd}` | Current working directory | `/path/to/current` |
| `${file}` | Full path of current file | `/path/to/file.lua` |
| `${file:cpp}` | Full path if filetype is cpp | `/path/to/file.cpp` |
| `${filename}` | Current filename | `file.lua` |
| `${filename:lua}` | Filename if filetype matches | `file.lua` |
| `${fileroot}` | File path without extension | `/path/to/file` |
| `${filedir}` | Directory of current file | `/path/to` |
| `${fileext}` | File extension | `lua` |
| `${filetype}` | Current buffer filetype | `lua` |
| `${home}` | User home directory | `/home/user` |
| `${tmpdir}` | System temp directory | `/tmp` |
| `${date}` | Current date (YYYY-MM-DD) | `2024-01-15` |
| `${time}` | Current time (HH:MM:SS) | `14:30:00` |
| `${timestamp}` | ISO timestamp | `2024-01-15T14:30:00` |
| `${env:VAR}` | Environment variable | Value of `$VAR` |
| `${prompt:Message}` | User input prompt | User-provided value |

### Macro Examples

```json
{
  "name": "Build Current File",
  "type": "build",
  "command": "gcc ${file} -o ${fileroot}.out",
  "cwd": "${wsdir}"
}
```

```json
{
  "name": "Run with Port",
  "type": "run",
  "command": "python server.py --port ${prompt:Enter port:8000}",
  "cwd": "${wsdir}"
}
```

---

## 📚 Usage Scenarios

### Scenario 1: Simple Build Workflow

**Goal**: Compile a C++ file and run it.

1. **Create workspace:**
   ```vim
   :Loop workspace create
   ```

2. **Add build task:**
   ```vim
   :Loop task add build
   ```
   Select "Build c++ file" template and customize:
   ```json
   {
     "name": "Compile",
     "type": "build",
     "command": "g++ -g -std=c++23 ${file:cpp} -o ${fileroot}.out",
     "cwd": "${wsdir}",
     "quickfix_matcher": "gcc",
     "depends_on": []
   }
   ```

3. **Add run task:**
   ```vim
   :Loop task add run
   ```
   Configure:
   ```json
   {
     "name": "Run",
     "type": "run",
     "command": "${fileroot}.out",
     "cwd": "${wsdir}",
     "depends_on": ["Compile"]
   }
   ```

4. **Execute:**
   ```vim
   :Loop task run Run
   ```

### Scenario 2: Complex Development Workflow

**Goal**: Set up a full development pipeline with linting, building, testing, and running.

1. **Create tasks:**
   ```json
   {
     "tasks": [
       {
         "name": "full-workflow",
         "type": "composite",
         "depends_on": ["setup", "lint", "build", "test", "run"],
         "depends_order": "sequence"
       },
       {
         "name": "setup",
         "type": "composite",
         "depends_on": ["install-deps"],
         "depends_order": "parallel"
       },
       {
         "name": "install-deps",
         "type": "vimcmd",
         "command": "lua vim.notify('Installing dependencies')",
         "depends_on": []
       },
       {
         "name": "lint",
         "type": "build",
         "command": "luacheck ${wsdir}",
         "cwd": "${wsdir}",
         "quickfix_matcher": "luacheck",
         "depends_on": ["install-deps"]
       },
       {
         "name": "build",
         "type": "build",
         "command": "make",
         "cwd": "${wsdir}",
         "quickfix_matcher": "gcc",
         "depends_on": ["lint"]
       },
       {
         "name": "test",
         "type": "run",
         "command": "npm test",
         "cwd": "${wsdir}",
         "depends_on": ["build"]
       },
       {
         "name": "run",
         "type": "run",
         "command": "npm start",
         "cwd": "${wsdir}",
         "depends_on": ["test"]
       }
     ]
   }
   ```

2. **Run the full workflow:**
   ```vim
   :Loop task run full-workflow
   ```

### Scenario 3: Parallel Task Execution

**Goal**: Run linting and formatting in parallel, then build.

```json
{
  "tasks": [
    {
      "name": "pre-build",
      "type": "composite",
      "depends_on": ["lint", "format"],
      "depends_order": "parallel"
    },
    {
      "name": "lint",
      "type": "build",
      "command": "eslint .",
      "cwd": "${wsdir}",
      "depends_on": []
    },
    {
      "name": "format",
      "type": "vimcmd",
      "command": "lua vim.lsp.buf.format()",
      "depends_on": []
    },
    {
      "name": "build",
      "type": "build",
      "command": "npm run build",
      "cwd": "${wsdir}",
      "depends_on": ["pre-build"]
    }
  ]
}
```

### Scenario 4: Language-Specific Workflows

#### Lua Project
```json
{
  "tasks": [
    {
      "name": "Check",
      "type": "build",
      "command": "luacheck ${wsdir}",
      "cwd": "${wsdir}",
      "quickfix_matcher": "luacheck",
      "depends_on": []
    },
    {
      "name": "Test",
      "type": "run",
      "command": "busted tests/",
      "cwd": "${wsdir}",
      "depends_on": ["Check"]
    }
  ]
}
```

#### Node.js Project
```json
{
  "tasks": [
    {
      "name": "Install",
      "type": "run",
      "command": "npm install",
      "cwd": "${wsdir}",
      "depends_on": []
    },
    {
      "name": "Lint",
      "type": "build",
      "command": "npm run lint",
      "cwd": "${wsdir}",
      "depends_on": ["Install"]
    },
    {
      "name": "Build",
      "type": "build",
      "command": "npm run build",
      "cwd": "${wsdir}",
      "depends_on": ["Lint"]
    },
    {
      "name": "Dev Server",
      "type": "run",
      "command": "npm run dev",
      "cwd": "${wsdir}",
      "depends_on": ["Build"]
    }
  ]
}
```

### Scenario 5: File-Specific Tasks

Use file-based macros to create tasks that work with the current file:

```json
{
  "name": "Compile Current C++ File",
  "type": "build",
  "command": "g++ -Wall -Wextra ${file:cpp} -o ${fileroot}.out",
  "cwd": "${filedir}",
  "quickfix_matcher": "gcc",
  "depends_on": []
}
```

```json
{
  "name": "Run Current Script",
  "type": "run",
  "command": "python ${file:python}",
  "cwd": "${filedir}",
  "depends_on": []
}
```

---

## 🎯 Task Execution Flow

When you execute a task, `loop.nvim` performs the following steps:

1. **Task Selection**: Identifies the task (or prompts you to select one)
2. **Dependency Resolution**: Builds a dependency graph and validates no circular dependencies
3. **Dry Run**: Validates task configuration and dependencies
4. **Macro Expansion**: Resolves all `${macro}` variables in task configurations
5. **Execution**: Runs tasks according to their dependency order (parallel or sequential)
6. **Progress Tracking**: Displays real-time progress in the Loop UI window
7. **Output Management**: Captures and displays task output in dedicated pages

---

## 🖥️ UI and Windows

### Loop Window

The Loop window displays:
- **Task Progress**: Visual tree showing task execution status
- **Output Pages**: Terminal output for each running task
- **Status Indicators**: Icons showing task state (waiting, running, success, failure)

### Page Management

Tasks create output pages organized by task type:
- Each task type gets its own page group
- Multiple tasks of the same type share a page group
- Switch between pages with `:Loop page switch`
- Open specific pages in your current window with `:Loop page open [group] [page]`

---

## 🔍 Tips and Best Practices

1. **Workspace Organization**: Create a workspace at your project root for project-wide tasks
2. **Task Naming**: Use descriptive names that indicate the task's purpose
3. **Dependency Management**: Keep dependency chains simple and avoid circular dependencies
4. **Macro Usage**: Leverage macros for file-specific and dynamic tasks
5. **Quickfix Matchers**: Use appropriate matchers for your build tools to get error navigation
6. **Composite Tasks**: Use composite tasks to organize complex workflows
7. **Parallel Execution**: Use `depends_order: "parallel"` for independent tasks to speed up execution

---

## 🤝 Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

---

## 📄 License

Distributed under the MIT License.
