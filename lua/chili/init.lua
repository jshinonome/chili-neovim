--- chili.nvim — Neovim plugin for kdb+/q process management and code execution.
--- Main entry point. Call require('chili').setup(opts) to initialize.
local M = {}

--- Default configuration
M._defaults = {
  config_path = nil, -- uses ~/.config/chili-tui/process-cfg.json by default
  timeout_secs = 5,
  output_position = "bottom", -- "bottom" | "right"
  output_height = 15,
  output_width = 80,
  keymaps = {
    send_all = "<C-a>",
    send_line = "<C-q>",
    send_selection = "<C-r>",
    process_view = "<leader>cp",
    toggle_output = "<leader>co",
  },
  lsp = {
    cmd = { "chiz", "server" },
    filetypes = { "chi", "pep" },
    document_highlight = true,
    format_on_save = true,
  },
  cmp = {
    keyword_length = 2,
  },
}

--- Active configuration
M._opts = {}

--- Whether setup has been called
M._initialized = false

--- Setup the plugin.
---@param opts table|nil user configuration
function M.setup(opts)
  if M._initialized then
    return
  end
  M._initialized = true

  M._opts = vim.tbl_deep_extend("force", M._defaults, opts or {})

  local ui = require("chili.ui")
  local execute = require("chili.execute")
  local process = require("chili.process")
  local lsp = require("chili.chiz")

  -- Wire up cross-module references
  execute.set_ui(ui)
  ui.set_opts(M._opts)
  lsp.set_opts(M._opts)

  -- Setup highlight groups
  ui.setup_highlights()

  -- Initial load of process tree
  process.reload()

  -- Register user commands
  M._register_commands()

  -- Register keymaps
  M._register_keymaps()

  -- Setup filetype detection for q files
  M._setup_filetype()

  -- Setup LSP, completion, and format-on-save
  lsp.setup()
end

--- Register user commands.
function M._register_commands()
  local ui = require("chili.ui")
  local execute = require("chili.execute")

  vim.api.nvim_create_user_command("ChiliProcessView", function()
    ui.toggle_process_view()
  end, { desc = "Toggle chili process view" })

  vim.api.nvim_create_user_command("ChiliProcessAdd", function()
    ui.add_process()
  end, { desc = "Add a new kdb+ process" })

  vim.api.nvim_create_user_command("ChiliProcessEdit", function()
    ui.edit_process()
  end, { desc = "Edit selected kdb+ process" })

  vim.api.nvim_create_user_command("ChiliConnect", function(cmd_opts)
    if cmd_opts.args and cmd_opts.args ~= "" then
      -- Connect by label
      local process_mod = require("chili.process")
      for _, node in ipairs(process_mod.nodes) do
        if node.type == "conn" and node.label == cmd_opts.args then
          process_mod.connect(node, function(err)
            if err then
              vim.notify("chili: " .. err, vim.log.levels.ERROR)
            else
              vim.notify("chili: Connected to " .. node.label, vim.log.levels.INFO)
            end
            ui.refresh_process_view()
          end)
          return
        end
      end
      vim.notify("chili: Process not found: " .. cmd_opts.args, vim.log.levels.WARN)
    else
      vim.notify("chili: Usage: :ChiliConnect <label>", vim.log.levels.WARN)
    end
  end, {
    desc = "Connect to a kdb+ process by label",
    nargs = "?",
    complete = function()
      local process_mod = require("chili.process")
      local labels = {}
      for _, node in ipairs(process_mod.nodes) do
        if node.type == "conn" then
          labels[#labels + 1] = node.label
        end
      end
      return labels
    end,
  })

  vim.api.nvim_create_user_command("ChiliDisconnect", function(cmd_opts)
    local process_mod = require("chili.process")
    local label = cmd_opts.args
    if not label or label == "" then
      label = process_mod.active_conn
    end
    if label then
      process_mod.disconnect(label)
      vim.notify("chili: Disconnected from " .. label, vim.log.levels.INFO)
      ui.refresh_process_view()
    else
      vim.notify("chili: No active connection", vim.log.levels.WARN)
    end
  end, {
    desc = "Disconnect from a kdb+ process",
    nargs = "?",
    complete = function()
      local process_mod = require("chili.process")
      local labels = {}
      for label, _ in pairs(process_mod.connections) do
        labels[#labels + 1] = label
      end
      return labels
    end,
  })

  vim.api.nvim_create_user_command("ChiliSendAll", function()
    execute.send_all()
  end, { desc = "Send entire buffer to active kdb+ connection" })

  vim.api.nvim_create_user_command("ChiliSendLine", function()
    execute.send_line()
  end, { desc = "Send current line to active kdb+ connection" })

  vim.api.nvim_create_user_command("ChiliSendSelection", function()
    execute.send_selection()
  end, { range = true, desc = "Send visual selection to active kdb+ connection" })

  vim.api.nvim_create_user_command("ChiliOutput", function()
    ui.toggle_output()
  end, { desc = "Toggle chili output buffer" })
end

--- Register keymaps.
function M._register_keymaps()
  local execute = require("chili.execute")
  local ui = require("chili.ui")
  local km = M._opts.keymaps

  -- Global keymaps (all buffers)
  if km.send_all then
    vim.keymap.set("n", km.send_all, function()
      execute.send_all()
    end, { noremap = true, silent = true, desc = "chili: Send all to kdb+" })
  end

  if km.send_line then
    vim.keymap.set("n", km.send_line, function()
      execute.send_line()
    end, { noremap = true, silent = true, desc = "chili: Send line to kdb+" })
  end

  if km.send_selection then
    vim.keymap.set("v", km.send_selection, function()
      execute.send_selection()
    end, { noremap = true, silent = true, desc = "chili: Send selection to kdb+" })
  end

  if km.process_view then
    vim.keymap.set("n", km.process_view, function()
      ui.toggle_process_view()
    end, { noremap = true, silent = true, desc = "chili: Toggle process view" })
  end

  if km.toggle_output then
    vim.keymap.set("n", km.toggle_output, function()
      ui.toggle_output()
    end, { noremap = true, silent = true, desc = "chili: Toggle output" })
  end
end

--- Setup filetype detection for q, chi, and pep files.
function M._setup_filetype()
  vim.filetype.add({
    extension = {
      q = "q",
      k = "q",
      chi = "chi",
      pep = "pep",
    },
  })
end

--- Return the active connection label for use in statusline.
--- Returns empty string if no active connection.
---@return string statusline text
function M.statusline()
  local process = require("chili.process")
  if not process.active_conn then
    return ""
  end
  return "󰒋 ◉ " .. process.active_conn
end

--- Return the color for the active connection.
--- For use with lualine's `color` option.
---@return table|nil lualine-compatible color table { fg }
function M.statusline_color()
  local process = require("chili.process")
  if not process.active_conn then
    return nil
  end

  local env = process.env_type(process.active_conn)
  local color_map = {
    dev = { fg = "#a6e3a1" },
    uat = { fg = "#f9e2af" },
    prod = { fg = "#f38ba8" },
    default = { fg = "#cdd6f4" },
  }
  return color_map[env] or color_map["default"]
end

return M
