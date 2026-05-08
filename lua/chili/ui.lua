--- UI components for chili.nvim.
--- Process view sidebar and output buffer.
local config = require("chili.config")
local process = require("chili.process")

local M = {}

--- Buffer and window IDs
M._process_buf = nil
M._process_win = nil
M._output_buf = nil
M._output_win = nil

--- User options (set from init.lua)
M._opts = {
  output_position = "bottom",
  output_height = 15,
  output_width = 80,
}

--- Set options from init.lua
---@param opts table
function M.set_opts(opts)
  M._opts = vim.tbl_deep_extend("force", M._opts, opts or {})
end

-- ── Process View ──────────────────────────────────────────────────────

--- Icon for tag groups based on environment name
---@param tag string
---@return string icon, string hl_group
local function tag_icon_and_hl(tag)
  local lower = tag:lower()
  if lower:find("dev") then
    return "󰛦", "ChiliTagDev"
  elseif lower:find("uat") or lower:find("qa") then
    return "󱍸", "ChiliTagUat"
  elseif lower:find("prod") or lower:find("prd") then
    return "󰒋", "ChiliTagProd"
  else
    return "󰓹", "ChiliTagDefault"
  end
end

--- Status icon for connections
---@param status string
---@return string icon, string hl_group
local function conn_icon_and_hl(status)
  if status == "connected" then
    return "◉", "ChiliConnected"
  else
    return "○", "ChiliDisconnected"
  end
end

--- Setup highlight groups
function M.setup_highlights()
  -- Tag colors (matching chili-tui Catppuccin palette)
  vim.api.nvim_set_hl(0, "ChiliTagDev", { fg = "#a6e3a1", bold = true })
  vim.api.nvim_set_hl(0, "ChiliTagUat", { fg = "#f9e2af", bold = true })
  vim.api.nvim_set_hl(0, "ChiliTagProd", { fg = "#f38ba8", bold = true })
  vim.api.nvim_set_hl(0, "ChiliTagDefault", { fg = "#89b2fa", bold = true })

  -- Connection status
  vim.api.nvim_set_hl(0, "ChiliConnected", { fg = "#a6e3a1" })
  vim.api.nvim_set_hl(0, "ChiliDisconnected", { fg = "#45475a" })

  -- UI elements
  vim.api.nvim_set_hl(0, "ChiliTitle", { fg = "#cba6f7", bold = true })
  vim.api.nvim_set_hl(0, "ChiliConnLabel", { fg = "#cdd6f4" })
  vim.api.nvim_set_hl(0, "ChiliConnDetail", { fg = "#45475a" })
  vim.api.nvim_set_hl(0, "ChiliSeparator", { fg = "#313244" })
  vim.api.nvim_set_hl(0, "ChiliOutputTime", { fg = "#f9e2af" })
  vim.api.nvim_set_hl(0, "ChiliOutputError", { fg = "#f38ba8" })
  vim.api.nvim_set_hl(0, "ChiliActive", { fg = "#1e1e2e", bg = "#b4befe", bold = true })

  -- Status bar
  vim.api.nvim_set_hl(0, "ChiliStatusDev", { fg = "#1e1e2e", bg = "#a6e3a1", bold = true })
  vim.api.nvim_set_hl(0, "ChiliStatusUat", { fg = "#1e1e2e", bg = "#f9e2af", bold = true })
  vim.api.nvim_set_hl(0, "ChiliStatusProd", { fg = "#1e1e2e", bg = "#f38ba8", bold = true })
  vim.api.nvim_set_hl(0, "ChiliStatusDefault", { fg = "#cdd6f4", bg = "#313244", bold = true })
end

--- Render the process tree into lines and highlights for the buffer.
---@return string[] lines
---@return table[] highlights list of { line, col_start, col_end, hl_group }
local function render_process_tree()
  local visible = config.visible_nodes(process.nodes)
  local lines = {}
  local highlights = {}

  for _, item in ipairs(visible) do
    local node = item.node
    local indent = string.rep("  ", node.depth)

    if node.type == "tag" then
      local arrow = node.expanded and "▼" or "▶"
      local icon, hl = tag_icon_and_hl(node.label)
      local line = string.format("%s%s %s %s", indent, arrow, icon, node.label)
      local line_idx = #lines
      lines[#lines + 1] = line
      highlights[#highlights + 1] = { line_idx, 0, #line, hl }
    else
      local icon, hl = conn_icon_and_hl(node.status)
      local detail = string.format(" %s:%d", node.host, node.port)
      local label_part = string.format("%s%s %s", indent, icon, node.label)
      local line = label_part .. detail
      local line_idx = #lines

      lines[#lines + 1] = line

      -- Icon highlight
      highlights[#highlights + 1] = { line_idx, #indent, #indent + #icon, hl }

      -- Label highlight
      local label_hl = node.status == "connected" and "ChiliConnected" or "ChiliConnLabel"
      highlights[#highlights + 1] = { line_idx, #indent + #icon + 1, #label_part, label_hl }

      -- Detail highlight
      local detail_hl = node.status == "connected" and "ChiliConnected" or "ChiliConnDetail"
      highlights[#highlights + 1] = { line_idx, #label_part, #line, detail_hl }
    end
  end

  if #lines == 0 then
    lines[1] = "  No processes configured"
    lines[2] = ""
    lines[3] = "  Press 'a' to add one"
    lines[4] = "  or edit ~/.config/chili-tui/process-cfg.json"
  end

  return lines, highlights
end

--- Create or get the process view buffer.
---@return integer bufnr
local function get_process_buf()
  if M._process_buf and vim.api.nvim_buf_is_valid(M._process_buf) then
    return M._process_buf
  end

  M._process_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M._process_buf, "chili://processes")
  vim.bo[M._process_buf].buftype = "nofile"
  vim.bo[M._process_buf].bufhidden = "hide"
  vim.bo[M._process_buf].swapfile = false
  vim.bo[M._process_buf].filetype = "chili-process"

  -- Set up keymaps for the process buffer
  local buf = M._process_buf
  local km_opts = { noremap = true, silent = true, buffer = buf }

  vim.keymap.set("n", "q", function()
    M.close_process_view()
  end, km_opts)

  vim.keymap.set("n", "<CR>", function()
    M._on_process_enter()
  end, km_opts)

  vim.keymap.set("n", "o", function()
    M._on_process_enter()
  end, km_opts)

  vim.keymap.set("n", "a", function()
    M.add_process()
  end, km_opts)

  vim.keymap.set("n", "e", function()
    M.edit_process()
  end, km_opts)

  vim.keymap.set("n", "d", function()
    M.delete_process()
  end, km_opts)

  vim.keymap.set("n", "r", function()
    process.reload()
    M.refresh_process_view()
  end, km_opts)

  vim.keymap.set("n", "c", function()
    M._set_active_under_cursor()
  end, km_opts)

  return M._process_buf
end

--- Refresh the process view buffer content.
function M.refresh_process_view()
  local buf = get_process_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines, highlights = render_process_tree()

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("chili_process")
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl[4], hl[1], hl[2], hl[3])
  end
end

--- Get the node under the cursor in the process view.
---@return ProcessNode|nil
---@return integer|nil index in process.nodes
local function get_node_under_cursor()
  if not M._process_win or not vim.api.nvim_win_is_valid(M._process_win) then
    return nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(M._process_win)
  local line_idx = cursor[1] -- 1-based

  local visible = config.visible_nodes(process.nodes)
  if line_idx > #visible then
    return nil, nil
  end

  local item = visible[line_idx]
  return item.node, item.index
end

--- Handle Enter key in the process view.
function M._on_process_enter()
  local node, idx = get_node_under_cursor()
  if not node then
    return
  end

  if node.type == "tag" then
    -- Toggle expand/collapse
    node.expanded = not node.expanded
    M.refresh_process_view()
  elseif node.type == "conn" then
    if node.status == "disconnected" then
      -- Connect
      vim.notify(string.format("chili: Connecting to %s:%d...", node.host, node.port), vim.log.levels.INFO)
      process.connect(node, function(err)
        if err then
          vim.notify("chili: " .. err, vim.log.levels.ERROR)
        else
          vim.notify(
            string.format("chili: Connected to %s (%s:%d)", node.label, node.host, node.port),
            vim.log.levels.INFO
          )
        end
        M.refresh_process_view()
      end)
    else
      -- Disconnect
      process.disconnect(node.label)
      vim.notify("chili: Disconnected from " .. node.label, vim.log.levels.INFO)
      M.refresh_process_view()
    end
  end
end

--- Set the connection under cursor as active.
function M._set_active_under_cursor()
  local node = get_node_under_cursor()
  if not node or node.type ~= "conn" then
    return
  end

  if node.status ~= "connected" then
    vim.notify("chili: Not connected to " .. node.label, vim.log.levels.WARN)
    return
  end

  process.set_active(node.label)
  vim.notify("chili: Active connection set to " .. node.label, vim.log.levels.INFO)
  M.refresh_process_view()
end

--- Open the process view sidebar.
function M.open_process_view()
  -- If already open, focus it
  if M._process_win and vim.api.nvim_win_is_valid(M._process_win) then
    vim.api.nvim_set_current_win(M._process_win)
    M.refresh_process_view()
    return
  end

  -- Reload process tree
  process.reload()

  local buf = get_process_buf()
  M.refresh_process_view()

  -- Open vertical split on the left
  vim.cmd("topleft vnew")
  M._process_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M._process_win, buf)
  vim.api.nvim_win_set_width(M._process_win, 36)

  -- Window options
  vim.wo[M._process_win].number = false
  vim.wo[M._process_win].relativenumber = false
  vim.wo[M._process_win].signcolumn = "no"
  vim.wo[M._process_win].foldcolumn = "0"
  vim.wo[M._process_win].wrap = false
  vim.wo[M._process_win].cursorline = true
  vim.wo[M._process_win].winfixwidth = true

  -- Set window title
  vim.wo[M._process_win].statusline = "%#ChiliTitle# 󰒋 Processes %#Normal#"
end

--- Close the process view sidebar.
function M.close_process_view()
  if M._process_win and vim.api.nvim_win_is_valid(M._process_win) then
    vim.api.nvim_win_close(M._process_win, true)
    M._process_win = nil
  end
end

--- Toggle the process view sidebar.
function M.toggle_process_view()
  if M._process_win and vim.api.nvim_win_is_valid(M._process_win) then
    M.close_process_view()
  else
    M.open_process_view()
  end
end

-- ── Add / Edit / Delete Process ───────────────────────────────────────

--- Prompt the user for process details and save.
---@param defaults table|nil pre-populated values for editing
function M.add_process(defaults)
  defaults = defaults or {}

  local fields = {
    { key = "label", prompt = "Label: ", default = defaults.label or "" },
    { key = "host", prompt = "Host: ", default = defaults.host or "localhost" },
    { key = "port", prompt = "Port: ", default = tostring(defaults.port or "") },
    { key = "user", prompt = "User: ", default = defaults.user or (os.getenv("USER") or "") },
    { key = "password", prompt = "Password: ", default = defaults.password or "" },
    { key = "tags", prompt = "Tags: ", default = defaults.tags or "" },
  }

  local values = {}
  local idx = 1

  local function prompt_next()
    if idx > #fields then
      -- All fields collected, validate and save
      local port = tonumber(values.port)
      if not port or port < 0 or port > 65535 then
        vim.notify("chili: Port must be a valid number (0-65535)", vim.log.levels.ERROR)
        return
      end
      if values.label == "" then
        vim.notify("chili: Label is required", vim.log.levels.ERROR)
        return
      end

      local tags = values.tags or ""
      local uniq_label = tags ~= "" and (tags .. "," .. values.label) or values.label

      local cfg = {
        label = values.label,
        host = values.host ~= "" and values.host or "localhost",
        port = port,
        user = values.user,
        password = values.password,
        enableTls = false,
        tags = tags,
        uniqLabel = uniq_label,
      }

      -- If editing, delete old entry first
      if defaults.uniq_label and defaults.uniq_label ~= "" and defaults.uniq_label ~= uniq_label then
        config.delete(defaults.uniq_label)
      end

      config.save_one(cfg)
      process.reload()
      M.refresh_process_view()
      vim.notify("chili: Process saved: " .. values.label, vim.log.levels.INFO)
      return
    end

    local field = fields[idx]
    vim.ui.input({
      prompt = field.prompt,
      default = field.default,
    }, function(input)
      if input == nil then
        -- User cancelled
        vim.notify("chili: Cancelled", vim.log.levels.INFO)
        return
      end
      values[field.key] = input
      idx = idx + 1
      prompt_next()
    end)
  end

  prompt_next()
end

--- Edit the process under cursor.
function M.edit_process()
  local node = get_node_under_cursor()
  if not node or node.type ~= "conn" then
    vim.notify("chili: Select a connection to edit", vim.log.levels.WARN)
    return
  end

  M.add_process({
    label = node.label,
    host = node.host,
    port = node.port,
    user = node.user,
    password = node.password,
    tags = node.tags,
    uniq_label = node.uniq_label,
  })
end

--- Delete the process under cursor.
function M.delete_process()
  local node = get_node_under_cursor()
  if not node or node.type ~= "conn" then
    vim.notify("chili: Select a connection to delete", vim.log.levels.WARN)
    return
  end

  vim.ui.input({
    prompt = string.format("Delete '%s'? (y/n): ", node.label),
  }, function(input)
    if input and input:lower() == "y" then
      -- Disconnect if connected
      if node.status == "connected" then
        process.disconnect(node.label)
      end
      config.delete(node.uniq_label)
      process.reload()
      M.refresh_process_view()
      vim.notify("chili: Deleted " .. node.label, vim.log.levels.INFO)
    end
  end)
end

-- ── Output Buffer ─────────────────────────────────────────────────────

--- Output buffer lines
M._output_lines = {}

--- Create or get the output buffer.
---@return integer bufnr
local function get_output_buf()
  if M._output_buf and vim.api.nvim_buf_is_valid(M._output_buf) then
    return M._output_buf
  end

  M._output_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M._output_buf, "chili://output")
  vim.bo[M._output_buf].buftype = "nofile"
  vim.bo[M._output_buf].bufhidden = "hide"
  vim.bo[M._output_buf].swapfile = false
  vim.bo[M._output_buf].filetype = "chili-output"

  -- Keymap to close
  vim.keymap.set("n", "q", function()
    M.close_output()
  end, { noremap = true, silent = true, buffer = M._output_buf })

  return M._output_buf
end

--- Append text to the output buffer with timestamp and elapsed time.
---@param text string result text
---@param elapsed number elapsed time in seconds
function M.append_output(text, elapsed)
  local now = os.date("%Y-%m-%d %H:%M:%S")
  local time_str = string.format("<--- %s %.6fs --->", now, elapsed)

  M._output_lines[#M._output_lines + 1] = time_str
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    M._output_lines[#M._output_lines + 1] = line
  end
  M._output_lines[#M._output_lines + 1] = ""

  M._refresh_output()

  -- Ensure output window is open
  if not M._output_win or not vim.api.nvim_win_is_valid(M._output_win) then
    M.open_output()
  end
end

--- Refresh the output buffer content.
function M._refresh_output()
  local buf = get_output_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M._output_lines)
  vim.bo[buf].modifiable = false

  -- Apply syntax highlighting
  local ns = vim.api.nvim_create_namespace("chili_output")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for i, line in ipairs(M._output_lines) do
    if line:match("^<---") then
      vim.api.nvim_buf_add_highlight(buf, ns, "ChiliOutputTime", i - 1, 0, -1)
    elseif line:match("^ERROR:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "ChiliOutputError", i - 1, 0, -1)
    end
  end

  -- Scroll to bottom if output window is open
  if M._output_win and vim.api.nvim_win_is_valid(M._output_win) then
    local line_count = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, M._output_win, { line_count, 0 })
  end
end

--- Open the output buffer.
function M.open_output()
  -- If already open, focus it
  if M._output_win and vim.api.nvim_win_is_valid(M._output_win) then
    return
  end

  local buf = get_output_buf()
  M._refresh_output()

  -- Open split
  if M._opts.output_position == "right" then
    vim.cmd("botright vnew")
    M._output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(M._output_win, M._opts.output_width)
  else
    vim.cmd("botright new")
    M._output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(M._output_win, M._opts.output_height)
  end

  vim.api.nvim_win_set_buf(M._output_win, buf)

  -- Window options
  vim.wo[M._output_win].number = false
  vim.wo[M._output_win].relativenumber = false
  vim.wo[M._output_win].signcolumn = "no"
  vim.wo[M._output_win].wrap = false
  vim.wo[M._output_win].cursorline = false
  vim.wo[M._output_win].winfixheight = true

  -- Set window title
  vim.wo[M._output_win].statusline = "%#ChiliTitle# 󰆍 Output %#Normal#"

  -- Return focus to previous window
  vim.cmd("wincmd p")
end

--- Close the output buffer.
function M.close_output()
  if M._output_win and vim.api.nvim_win_is_valid(M._output_win) then
    vim.api.nvim_win_close(M._output_win, true)
    M._output_win = nil
  end
end

--- Toggle the output buffer.
function M.toggle_output()
  if M._output_win and vim.api.nvim_win_is_valid(M._output_win) then
    M.close_output()
  else
    M.open_output()
  end
end

return M
