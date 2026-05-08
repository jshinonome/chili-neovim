--- Connection state management for chili.nvim.
--- Tracks active connections and the currently selected one.
local ipc = require("chili.ipc")
local config = require("chili.config")

local M = {}

--- Connection state
---@type table<string, { handle: QConn, host: string, port: integer, status: string, tags: string }>
M.connections = {}

--- Currently active connection label
---@type string|nil
M.active_conn = nil

--- Process tree nodes (loaded from config)
---@type ProcessNode[]
M.nodes = {}

--- Reload the process tree from config.
function M.reload()
  local cfgs = config.load()
  M.nodes = config.build_tree(cfgs)

  -- Preserve connection status for existing connections
  for _, node in ipairs(M.nodes) do
    if node.type == "conn" and M.connections[node.label] then
      node.status = "connected"
    end
  end
end

--- Connect to a process node.
---@param node ProcessNode
---@param callback fun(err: string|nil)
function M.connect(node, callback)
  if node.type ~= "conn" then
    callback("Not a connection node")
    return
  end

  if M.connections[node.label] then
    callback("Already connected to " .. node.label)
    return
  end

  ipc.connect(node.host, node.port, node.user, node.password, 5, function(err, conn)
    if err then
      callback(err)
      return
    end

    M.connections[node.label] = {
      handle = conn,
      host = node.host,
      port = node.port,
      status = "connected",
      tags = node.tags or "",
    }

    -- Update node status
    node.status = "connected"

    -- Set as active connection
    M.active_conn = node.label

    callback(nil)
  end)
end

--- Disconnect from a connection by label.
---@param label string
function M.disconnect(label)
  local conn_info = M.connections[label]
  if conn_info then
    ipc.disconnect(conn_info.handle)
    M.connections[label] = nil

    -- Update node status
    for _, node in ipairs(M.nodes) do
      if node.type == "conn" and node.label == label then
        node.status = "disconnected"
      end
    end

    -- Clear active if it was this one
    if M.active_conn == label then
      M.active_conn = nil
    end
  end
end

--- Get the active connection handle.
---@return QConn|nil handle
---@return string|nil label
function M.get_active()
  if not M.active_conn then
    return nil, nil
  end
  local conn_info = M.connections[M.active_conn]
  if not conn_info then
    M.active_conn = nil
    return nil, nil
  end
  return conn_info.handle, M.active_conn
end

--- Set the active connection.
---@param label string
---@return boolean success
function M.set_active(label)
  if M.connections[label] then
    M.active_conn = label
    return true
  end
  return false
end

--- Get the environment color type for a connection label.
--- Returns "dev", "uat", "prod", or "default".
---@param label string
---@return string
function M.env_type(label)
  if not label then
    return "default"
  end
  local lower = label:lower()
  -- Check tags first, then label
  local conn_info = M.connections[label]
  local tags = conn_info and conn_info.tags or ""
  local check = (tags .. " " .. lower):lower()

  if check:find("prod") or check:find("prd") then
    return "prod"
  elseif check:find("uat") or check:find("qa") then
    return "uat"
  elseif check:find("dev") then
    return "dev"
  end
  return "default"
end

--- List all connections with their statuses.
---@return table[]
function M.list()
  local result = {}
  for label, info in pairs(M.connections) do
    result[#result + 1] = {
      label = label,
      host = info.host,
      port = info.port,
      status = info.status,
      active = (label == M.active_conn),
    }
  end
  return result
end

return M
