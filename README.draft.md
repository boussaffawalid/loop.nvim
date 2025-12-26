# loop.nvim

<p align="center">
  <strong>Advanced Workspace and Task Management for Neovim.</strong>
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
> **Work in Progress**: This plugin is in early development.
> Interface, APIs and configurations are subject to change.

## 📖 Introduction

**loop.nvim** Is a workspace and task manager for Neovim. It allows you to define workspaces with specific configurations and run complex, dependency-aware tasks directly from your editor.

Unlike simple term runners, `loop.nvim` introduces the concept of **Workspaces** (stored in a `.nvimloop` directory) to manage project state, task definitions, and UI layouts.

### ✨ Key Features

* **Workspace Management:** Automatically detects and loads project configurations from `.nvimloop` directories.
* **Task Scheduling:** Run, repeat, and terminate tasks with dependency resolution and macro expansion.
* **Dry Runs:** Automatically performs dry-runs before execution to validate task paths and dependencies.
* **Smart Auto-Save:** Automatically saves modified files within the workspace scope before running tasks.
* **UI Management:** Built-in window and page management for task outputs.
* **Lazy Loading:** Light initialization that only fully loads when a workspace is detected or a command is triggered.

---

## ⚡ Requirements

* Neovim >= **0.10**

---

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

~~~lua
{
    "mbfoss/loop.nvim",
    cmd = { "Loop" }, -- Lazy load on the command
    config = function()
        require("loop").setup({
            -- Optional global configuration
        })
    end
}
~~~

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

~~~lua
use {
    'mbfoss/loop.nvim',
    config = function()
        require('loop').setup()
    end
}
~~~

---

## ⚙️ Configuration

### Global Setup
You can pass options to the `setup` function to customize symbols and selectors.

~~~lua
require("loop").setup({
    selector = "builtin", -- UI selector to use
    window = {
        symbols = {
            change  = "●",
            success = "✓",
            failure = "✗",
        },
    },
    -- Custom macros can be injected here
    macros = {}, 
})
~~~

### Workspace Configuration
When you run `:Loop workspace create`, a `.nvimloop` directory is created in your project root. This directory contains your local configuration (`workspace.json`) and task definitions.

`loop.nvim` automatically detects this folder on `VimEnter` and loads the workspace.

---

## 🚀 Usage

The primary interaction is through the `:Loop` user command.

### Workspace Commands

| Command | Description |
| :--- | :--- |
| `:Loop workspace create` | Initialize a new workspace (creates `.nvimloop`) in CWD. |
| `:Loop workspace open` | Open the workspace from the current directory. |
| `:Loop workspace configure` | Open/check the current `workspace.json` configuration. |
| `:Loop workspace close` | Close the current workspace and terminate running tasks. |
| `:Loop workspace save_files` | Save workspace files (as defined in the workspace configuration). |

### Task Commands

| Command | Description |
| :--- | :--- |
| `:Loop task run [name]` | Run a specific task. If name is omitted, opens selector. |
| `:Loop task repeat` | Repeat the last executed task. |
| `:Loop task add [type]` | Create a new task of a specific type. |
| `:Loop task configure` | Open task file. |
| `:Loop task configure [name]` | Configure a specific task generator (if it supports configuration). |
| `:Loop task terminate` | Stop all currently running tasks. |

### Window / UI Commands

| Command | Description |
| :--- | :--- |
| `:Loop toggle` | Toggle the Loop UI window. |
| `:Loop page switch` | Switch between active output pages. |
| `:Loop page open [page]` | Open a specific page group in the current window. |

---

## 🧩 Task Runner Logic

When you execute a task, `loop.nvim` performs the following steps:

1.  **Selection:** Identifies the task (or asks you to select one).
2.  **Dry Run:** Simulates the execution tree to check for missing dependencies or configuration errors.
3.  **Macros:** Resolves macros.
5.  **Execution:** Runs the task scheduler.

---

## 🤝 Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

---

## 📄 License

Distributed under the MIT License.
