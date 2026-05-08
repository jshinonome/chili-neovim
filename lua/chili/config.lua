--- Process configuration management for chili.nvim.
--- Reads/writes ~/.config/chili-tui/process-cfg.json (shared with chili-tui).
local M = {}

--- Default config directory and file
local APP_NAME = "chili-neovim"
local CFG_FILE = "process-cfg.json"

--- Get the config file path: ~/.config/chili-neovim/process-cfg.json
---@return string
function M.cfg_path()
  local config_dir = vim.fn.stdpath("config")
  -- Use XDG config dir like chili-tui does
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    config_dir = xdg
  else
    config_dir = vim.fn.expand("~/.config")
  end
  return config_dir .. "/" .. APP_NAME .. "/" .. CFG_FILE
end

--- Load process configurations from JSON file.
---@return table[] list of ProcessCfg entries
function M.load()
  local path = M.cfg_path()
  local f = io.open(path, "r")
  if not f then
    -- Create config dir and empty config if it doesn't exist
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    f = io.open(path, "w")
    if f then
      f:write("[]")
      f:close()
    end
    return {}
  end

  local content = f:read("*a")
  f:close()

  local ok, cfgs = pcall(vim.json.decode, content)
  if not ok or type(cfgs) ~= "table" then
    return {}
  end

  -- Ensure defaults for each config entry
  for _, cfg in ipairs(cfgs) do
    cfg.host = cfg.host or "localhost"
    cfg.port = cfg.port or 0
    cfg.user = cfg.user or ""
    cfg.password = cfg.password or ""
    cfg.enableTls = cfg.enableTls or false
    cfg.label = cfg.label or ""
    cfg.tags = cfg.tags or ""
    cfg.uniqLabel = cfg.uniqLabel or ""
  end

  return cfgs
end

--- Simple JSON pretty-printer for arrays of objects.
---@param tbl table the table to encode
---@return string pretty-printed JSON
local function json_pretty(tbl)
  -- Encode each top-level entry on its own set of lines
  local entries = {}
  for _, item in ipairs(tbl) do
    local parts = {}
    -- Maintain a consistent key order matching chili-tui
    local key_order = { "host", "port", "user", "password", "enableTls", "label", "tags", "uniqLabel" }
    for _, k in ipairs(key_order) do
      local v = item[k]
      if v ~= nil then
        local val_str
        if type(v) == "string" then
          val_str = vim.json.encode(v)
        elseif type(v) == "boolean" then
          val_str = v and "true" or "false"
        else
          val_str = tostring(v)
        end
        parts[#parts + 1] = string.format('    "%s": %s', k, val_str)
      end
    end
    entries[#entries + 1] = "  {\n" .. table.concat(parts, ",\n") .. "\n  }"
  end
  return "[\n" .. table.concat(entries, ",\n") .. "\n]\n"
end

--- Save process configurations to JSON file.
---@param cfgs table[] list of ProcessCfg entries
function M.save(cfgs)
  local path = M.cfg_path()

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Sort by uniqLabel for consistent ordering
  table.sort(cfgs, function(a, b)
    return (a.uniqLabel or "") < (b.uniqLabel or "")
  end)

  local json = json_pretty(cfgs)

  local f = io.open(path, "w")
  if f then
    f:write(json)
    f:close()
  end
end

--- Save a single ProcessCfg, adding or replacing by uniqLabel.
---@param cfg table ProcessCfg entry
function M.save_one(cfg)
  local cfgs = M.load()

  -- Remove existing entry with same uniqLabel if present
  local new_cfgs = {}
  for _, c in ipairs(cfgs) do
    if c.uniqLabel ~= cfg.uniqLabel then
      new_cfgs[#new_cfgs + 1] = c
    end
  end
  new_cfgs[#new_cfgs + 1] = cfg

  M.save(new_cfgs)
end

--- Delete a process config by uniqLabel.
---@param uniq_label string
function M.delete(uniq_label)
  local cfgs = M.load()
  local new_cfgs = {}
  for _, c in ipairs(cfgs) do
    if c.uniqLabel ~= uniq_label then
      new_cfgs[#new_cfgs + 1] = c
    end
  end
  M.save(new_cfgs)
end

--- Process node types for the tree view
---@alias ProcessNodeType "tag" | "conn"

---@class ProcessNode
---@field type ProcessNodeType
---@field label string
---@field depth integer
---@field expanded boolean
---@field host? string
---@field port? integer
---@field user? string
---@field password? string
---@field enable_tls? boolean
---@field tags? string
---@field status? string "disconnected" | "connected"
---@field uniq_label? string

--- Build a process tree from a flat list of configs.
--- Groups connections by tags (matching chili-tui behavior).
---@param cfgs table[] list of ProcessCfg entries
---@return ProcessNode[] tree nodes
function M.build_tree(cfgs)
  -- Sort by tags then label
  table.sort(cfgs, function(a, b)
    if a.tags == b.tags then
      return a.label < b.label
    end
    return a.tags < b.tags
  end)

  local nodes = {}

  -- Group by tags
  local tag_groups = {} -- ordered list of { tag, conns }
  local tag_index = {} -- tag -> index in tag_groups
  local untagged = {}

  for _, cfg in ipairs(cfgs) do
    if cfg.tags == "" then
      untagged[#untagged + 1] = cfg
    else
      if not tag_index[cfg.tags] then
        tag_index[cfg.tags] = #tag_groups + 1
        tag_groups[#tag_groups + 1] = { tag = cfg.tags, conns = {} }
      end
      local group = tag_groups[tag_index[cfg.tags]]
      group.conns[#group.conns + 1] = cfg
    end
  end

  -- Sort tag groups
  table.sort(tag_groups, function(a, b)
    return a.tag < b.tag
  end)

  -- Add tagged groups
  for _, group in ipairs(tag_groups) do
    local tag_label = group.tag:gsub(",", "/")
    nodes[#nodes + 1] = {
      type = "tag",
      label = tag_label,
      depth = 0,
      expanded = true,
      raw_tag = group.tag,
    }

    for _, cfg in ipairs(group.conns) do
      nodes[#nodes + 1] = {
        type = "conn",
        label = cfg.label,
        host = (cfg.host == "" and "localhost" or cfg.host),
        port = cfg.port,
        user = (cfg.user == "" and (os.getenv("USER") or "") or cfg.user),
        password = cfg.password or "",
        enable_tls = cfg.enableTls or false,
        tags = cfg.tags or "",
        status = "disconnected",
        depth = 1,
        uniq_label = cfg.uniqLabel or "",
      }
    end
  end

  -- Add untagged connections at root
  for _, cfg in ipairs(untagged) do
    nodes[#nodes + 1] = {
      type = "conn",
      label = cfg.label,
      host = (cfg.host == "" and "localhost" or cfg.host),
      port = cfg.port,
      user = (cfg.user == "" and (os.getenv("USER") or "") or cfg.user),
      password = cfg.password or "",
      enable_tls = cfg.enableTls or false,
      tags = "",
      status = "disconnected",
      depth = 0,
      uniq_label = cfg.uniqLabel or "",
    }
  end

  return nodes
end

--- Get visible nodes (respecting collapsed tags).
---@param nodes ProcessNode[]
---@return table[] list of { index, node }
function M.visible_nodes(nodes)
  local result = {}
  local skip_depth = nil

  for idx, node in ipairs(nodes) do
    if skip_depth then
      if node.depth > skip_depth then
        goto continue
      else
        skip_depth = nil
      end
    end

    result[#result + 1] = { index = idx, node = node }

    if node.type == "tag" and not node.expanded then
      skip_depth = node.depth
    end

    ::continue::
  end

  return result
end

return M
