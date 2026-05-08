--- Code execution module for chili.nvim.
--- Sends q code to the active kdb+ connection.
local ipc = require("chili.ipc")
local process = require("chili.process")

local M = {}

--- Reference to the UI module (set during init to avoid circular deps)
---@type table|nil
M._ui = nil

--- Set the UI module reference.
---@param ui table
function M.set_ui(ui)
  M._ui = ui
end

--- Wrap code with .Q.S formatting, matching chili-tui behavior.
---@param code string raw q code
---@return string wrapped expression
local function wrap_code(code)
  local escaped = code:gsub("\\", "\\\\"):gsub('"', '\\"')
  return string.format('{.Q.S[50 160;0j;value x]}"%s"', escaped)
end

--- Execute code on the active connection.
---@param code string the q code to execute
function M.execute(code)
  local handle, label = process.get_active()
  if not handle then
    vim.notify("chili: No active connection", vim.log.levels.WARN)
    return
  end

  local expr = wrap_code(code)
  local start_time = vim.uv.hrtime()

  ipc.execute(handle, expr, function(err, result)
    local elapsed = (vim.uv.hrtime() - start_time) / 1e9

    if err then
      if M._ui then
        M._ui.append_output("ERROR: " .. err, elapsed)
      end
      vim.notify(string.format("chili: Error on %s: %s", label or "?", err), vim.log.levels.ERROR)
    else
      if M._ui then
        M._ui.append_output(result or "", elapsed)
      end
    end
  end)
end

--- Send entire buffer content to the active connection.
function M.send_all()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local code = table.concat(lines, "\n")
  if code:match("^%s*$") then
    vim.notify("chili: Buffer is empty", vim.log.levels.WARN)
    return
  end
  M.execute(code)
end

--- Send the current line to the active connection.
function M.send_line()
  local line = vim.api.nvim_get_current_line()
  if line:match("^%s*$") then
    vim.notify("chili: Current line is empty", vim.log.levels.WARN)
    return
  end
  M.execute(line)
end

--- Send the visual selection to the active connection.
function M.send_selection()
  -- Exit visual mode first to get the marks
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)

  vim.schedule(function()
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")

    local start_line = start_pos[1] - 1
    local end_line = end_pos[1] - 1

    if start_line < 0 or end_line < 0 then
      vim.notify("chili: No selection", vim.log.levels.WARN)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, false)

    -- Handle character-level selection for single line
    if start_line == end_line and #lines > 0 then
      local start_col = start_pos[2]
      local end_col = end_pos[2]
      -- end_col can be very large for line-wise selection
      end_col = math.min(end_col + 1, #lines[1])
      lines[1] = lines[1]:sub(start_col + 1, end_col)
    elseif #lines > 0 then
      -- Trim first and last lines for character-level selection
      local start_col = start_pos[2]
      local end_col = end_pos[2]
      lines[1] = lines[1]:sub(start_col + 1)
      if #lines > 1 then
        end_col = math.min(end_col + 1, #lines[#lines])
        lines[#lines] = lines[#lines]:sub(1, end_col)
      end
    end

    local code = table.concat(lines, "\n")
    if code:match("^%s*$") then
      vim.notify("chili: Selection is empty", vim.log.levels.WARN)
      return
    end

    M.execute(code)
  end)
end

return M
