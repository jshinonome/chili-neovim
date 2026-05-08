# 🌶 chili.nvim

A Neovim plugin for kdb+/q process management and code execution, with built-in IPC support.

## Features

- **Process Manager** — sidebar tree view of kdb+ connections, grouped by tags
- **kdb+ IPC** — async TCP communication using protocol version 6 (little-endian)
- **Code Execution** — send entire buffer, current line, or visual selection to the active connection
- **Output Buffer** — timestamped results in a split window
- **Syntax Highlighting** — bundled syntax files for q, chi, and pep

## Requirements

- Neovim ≥ 0.9
- A Nerd Font (for sidebar icons)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jshinonome/chili-neovim",
  config = function()
    require("chili").setup()
  end,
}
```

### Manual

Clone the repo and add to your runtime path:

```vim
set runtimepath+=~/path/to/chili.nvim
```

## Configuration

All options are optional:

```lua
require("chili").setup({
  output_position = "bottom",  -- "bottom" | "right"
  output_height = 15,          -- rows for bottom split
  output_width = 80,           -- cols for right split
  keymaps = {
    send_all       = "<C-a>",       -- send entire buffer
    send_line      = "<C-q>",       -- send current line
    send_selection = "<C-e>",       -- send visual selection
    process_view   = "<leader>cp",  -- toggle process sidebar
    toggle_output  = "<leader>co",  -- toggle output buffer
  },
})
```

## Process Configuration

filepath: `~/.config/chili-neovim/process-cfg.json`:

```json
[
  {
    "host": "localhost",
    "port": 5001,
    "user": "",
    "password": "",
    "enableTls": false,
    "label": "hdb",
    "tags": "dev",
    "uniqLabel": "dev,hdb"
  }
]
```

Tags create collapsible groups in the process sidebar. The active connection label is color-coded:

- 🟢 **Green** — `dev`
- 🟡 **Yellow** — `uat` / `qa`
- 🔴 **Red** — `prod` / `prd`

## Commands

| Command                    | Description                           |
| -------------------------- | ------------------------------------- |
| `:ChiliProcessView`        | Toggle process tree sidebar           |
| `:ChiliProcessAdd`         | Add a new kdb+ process                |
| `:ChiliProcessEdit`        | Edit process under cursor             |
| `:ChiliConnect <label>`    | Connect to a process (tab-completion) |
| `:ChiliDisconnect [label]` | Disconnect (defaults to active)       |
| `:ChiliSendAll`            | Execute entire buffer                 |
| `:ChiliSendLine`           | Execute current line                  |
| `:ChiliSendSelection`      | Execute visual selection              |
| `:ChiliOutput`             | Toggle output buffer                  |

## Keybindings

### Global (configurable via `setup()`)

| Key          | Mode | Action                |
| ------------ | ---- | --------------------- |
| `<C-a>`      | n    | Send entire buffer    |
| `<C-q>`      | n    | Send current line     |
| `<C-e>`      | v    | Send visual selection |
| `<leader>cp` | n    | Toggle process view   |
| `<leader>co` | n    | Toggle output buffer  |

### Process Sidebar

| Key           | Action                            |
| ------------- | --------------------------------- |
| `Enter` / `o` | Connect / disconnect / toggle tag |
| `a`           | Add process                       |
| `e`           | Edit process                      |
| `d`           | Delete process                    |
| `c`           | Set as active connection          |
| `r`           | Refresh process tree              |
| `q`           | Close sidebar                     |

## Supported Filetypes

| Extension  | Filetype |
| ---------- | -------- |
| `.q`, `.k` | q        |
| `.chi`     | chi      |
| `.pep`     | pep      |

## License

MIT
