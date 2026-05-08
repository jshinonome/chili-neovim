--- kdb+ IPC protocol implementation for Neovim.
--- Port of connector.rs and serde6.rs from chili-tui.
--- Uses vim.uv (libuv) for TCP connections.
local M = {}

--- Build auth credential bytes: "user:password\x03\x00"
---@param user string
---@param password string
---@return string binary auth bytes
function M.auth_bytes(user, password)
  return user .. ":" .. password .. "\x03\x00"
end

--- Serialize a string as a kdb+ IPC sync request message.
--- Format: 8-byte header + char vector (type 10)
---@param expr string the q expression to send
---@return string binary message bytes
function M.serialize_string(expr)
  expr = expr:match("^%s*(.-)%s*$") or expr -- trim

  local payload_len = 6 + #expr -- type(1) + attr(1) + len(4) + data
  local total_len = 8 + payload_len

  local bytes = {}
  -- Header: endianness(1) + msg_type(1) + compression(1) + reserved(1) + length(4)
  bytes[#bytes + 1] = string.char(1, 1, 0, 0) -- little-endian, sync, no compression
  -- Total length as u32 LE
  bytes[#bytes + 1] = string.char(
    total_len % 256,
    math.floor(total_len / 256) % 256,
    math.floor(total_len / 65536) % 256,
    math.floor(total_len / 16777216) % 256
  )
  -- Char vector: type(10) + attr(0) + length(u32 LE) + data
  bytes[#bytes + 1] = string.char(10, 0)
  local expr_len = #expr
  bytes[#bytes + 1] = string.char(
    expr_len % 256,
    math.floor(expr_len / 256) % 256,
    math.floor(expr_len / 65536) % 256,
    math.floor(expr_len / 16777216) % 256
  )
  bytes[#bytes + 1] = expr

  return table.concat(bytes)
end

--- Read a u32 little-endian value from a byte string at 1-based position.
---@param data string
---@param pos integer 1-based position
---@return integer
local function read_u32_le(data, pos)
  local b0, b1, b2, b3 = data:byte(pos, pos + 3)
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

--- Read a u64 little-endian value from a byte string at 1-based position.
---@param data string
---@param pos integer 1-based position
---@return integer
local function read_u64_le(data, pos)
  local lo = read_u32_le(data, pos)
  local hi = read_u32_le(data, pos + 4)
  return lo + hi * 4294967296
end

--- Decompress kdb+ IPC compressed payload.
--- Port of serde6::decompress from chili-tui.
---@param vec string compressed data
---@param start_pos integer 1-based start position in vec (5 for mode 1, 9 for mode 2)
---@param decompressed_len integer expected decompressed length
---@return string decompressed data
function M.decompress(vec, start_pos, decompressed_len)
  local de = {}
  for i = 1, decompressed_len do
    de[i] = 0
  end

  local d_pos = 1 -- 1-based index into de
  local x_pos = 5 -- offset counter (mirrors Rust x_pos=4 but 1-based)
  local c_pos = start_pos -- 1-based index into vec
  local x = {}
  for i = 0, 255 do
    x[i] = 0
  end
  local n = 0
  local i_bit = 0

  while d_pos <= decompressed_len do
    if i_bit == 0 then
      n = vec:byte(c_pos)
      c_pos = c_pos + 1
      i_bit = 1
    end

    local r = 0
    if (n % (i_bit * 2)) >= i_bit then
      -- compressed reference
      local s = x[vec:byte(c_pos)] + 1 -- convert 0-based to 1-based
      c_pos = c_pos + 1
      r = vec:byte(c_pos)
      c_pos = c_pos + 1
      for j = 0, r + 1 do
        de[d_pos + j] = de[s + j]
      end
      d_pos = d_pos + 2
    else
      -- literal byte
      de[d_pos] = vec:byte(c_pos)
      d_pos = d_pos + 1
      c_pos = c_pos + 1
    end

    -- Update hash table
    for idx = x_pos, d_pos - 2 do
      if idx >= 1 and idx + 1 <= decompressed_len then
        local xor_val = bit.bxor(de[idx], de[idx + 1])
        x[xor_val % 256] = idx - 1 -- store 0-based
      end
    end

    x_pos = d_pos - 1

    if (n % (i_bit * 2)) >= i_bit then
      d_pos = d_pos + r
      x_pos = d_pos
    end

    i_bit = i_bit * 2
    if i_bit >= 256 then
      i_bit = 0
    end
  end

  -- Convert byte array to string
  local chars = {}
  for idx = 1, decompressed_len do
    chars[idx] = string.char(de[idx])
  end
  return table.concat(chars)
end

--- Deserialize a kdb+ IPC response payload into a string.
--- Supports: string (type 10), general list (type 0), error (type 128/-128).
---@param data string binary payload
---@param pos integer 1-based position (mutable via table wrapper)
---@return string|nil result
---@return string|nil error
function M.deserialize(data, pos_ref)
  if #data == 0 then
    return "", nil
  end

  local k_type = data:byte(pos_ref[1])
  pos_ref[1] = pos_ref[1] + 1
  local start_pos = pos_ref[1]

  if k_type == 0 then
    -- General list (type 0) — e.g. .Q.S returns list of strings
    pos_ref[1] = pos_ref[1] + 1 -- attributes byte
    local length = read_u32_le(data, pos_ref[1])
    pos_ref[1] = pos_ref[1] + 4
    local lines = {}
    for _ = 1, length do
      local result, err = M.deserialize(data, pos_ref)
      if err then
        return nil, err
      end
      lines[#lines + 1] = result
    end
    return table.concat(lines, "\n"), nil
  elseif k_type == 10 then
    -- String / char vector (type 10)
    pos_ref[1] = pos_ref[1] + 1 -- attributes byte
    local length = read_u32_le(data, pos_ref[1])
    pos_ref[1] = pos_ref[1] + 4
    local s = data:sub(pos_ref[1], pos_ref[1] + length - 1)
    pos_ref[1] = pos_ref[1] + length
    return s, nil
  elseif k_type == 128 then
    -- Server error (type 128 = -128 unsigned)
    local eod = pos_ref[1]
    while eod <= #data and data:byte(eod) ~= 0 do
      eod = eod + 1
    end
    local msg = data:sub(start_pos, eod - 1)
    pos_ref[1] = eod
    return nil, msg
  else
    return string.format("[k type %d]", k_type), nil
  end
end

--- Connection handle type
---@class QConn
---@field client uv_tcp_t
---@field connected boolean

--- Connect to a kdb+ process (synchronous, called from async context).
--- Uses vim.uv for TCP.
---@param host string
---@param port integer
---@param user string
---@param password string
---@param timeout_secs integer
---@param callback fun(err: string|nil, conn: QConn|nil)
function M.connect(host, port, user, password, timeout_secs, callback)
  if not host or host == "" or host == "localhost" then
    host = "127.0.0.1"
  end

  local client = vim.uv.new_tcp()
  if not client then
    callback("Failed to create TCP socket", nil)
    return
  end

  -- Set up timeout
  local timer = vim.uv.new_timer()
  local timed_out = false

  if timeout_secs > 0 and timer then
    timer:start(timeout_secs * 1000, 0, function()
      if not timed_out then
        timed_out = true
        timer:stop()
        timer:close()
        client:close()
        vim.schedule(function()
          callback("Connection timed out", nil)
        end)
      end
    end)
  end

  client:connect(host, port, function(err)
    if timed_out then
      return
    end

    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end

    if err then
      client:close()
      vim.schedule(function()
        callback("Connection failed: " .. err, nil)
      end)
      return
    end

    -- Send auth handshake
    local auth = M.auth_bytes(user, password)
    client:write(auth, function(write_err)
      if write_err then
        client:close()
        vim.schedule(function()
          callback("Auth write failed: " .. write_err, nil)
        end)
        return
      end

      -- Read 1-byte auth response
      client:read_start(function(read_err, data)
        client:read_stop()

        if read_err then
          client:close()
          vim.schedule(function()
            callback("Auth read failed: " .. read_err, nil)
          end)
          return
        end

        if not data or #data < 1 then
          client:close()
          vim.schedule(function()
            callback("Authentication failed: no response", nil)
          end)
          return
        end

        local version = data:byte(1)
        if version < 1 then
          client:close()
          vim.schedule(function()
            callback("Authentication failed", nil)
          end)
          return
        end

        local conn = {
          client = client,
          connected = true,
        }

        vim.schedule(function()
          callback(nil, conn)
        end)
      end)
    end)
  end)
end

--- Disconnect from a kdb+ process.
---@param conn QConn
function M.disconnect(conn)
  if conn and conn.client and conn.connected then
    conn.connected = false
    if not conn.client:is_closing() then
      conn.client:close()
    end
  end
end

--- Execute a q expression on a connection (async).
--- Sends a sync request and reads the response.
---@param conn QConn
---@param expr string the q expression
---@param callback fun(err: string|nil, result: string|nil)
function M.execute(conn, expr, callback)
  if not conn or not conn.connected then
    vim.schedule(function()
      callback("Not connected", nil)
    end)
    return
  end

  local msg = M.serialize_string(expr)

  conn.client:write(msg, function(write_err)
    if write_err then
      vim.schedule(function()
        callback("Write failed: " .. write_err, nil)
      end)
      return
    end

    -- Read response: accumulate data until we have the full message
    local buf = ""
    local header_parsed = false
    local expected_len = 0
    local compression_mode = 0

    conn.client:read_start(function(read_err, data)
      if read_err then
        conn.client:read_stop()
        vim.schedule(function()
          callback("Read failed: " .. read_err, nil)
        end)
        return
      end

      if not data then
        conn.client:read_stop()
        vim.schedule(function()
          callback("Connection closed", nil)
        end)
        return
      end

      buf = buf .. data

      -- Parse header once we have 8 bytes
      if not header_parsed and #buf >= 8 then
        local encoding = buf:byte(1)
        if encoding == 0 then
          conn.client:read_stop()
          vim.schedule(function()
            callback("Big-endian not supported", nil)
          end)
          return
        end

        compression_mode = buf:byte(3)
        expected_len = read_u32_le(buf, 5)
        expected_len = expected_len + buf:byte(4) * 4294967296

        header_parsed = true
      end

      -- Check if we have the full message
      if header_parsed and #buf >= expected_len then
        conn.client:read_stop()

        local payload = buf:sub(9, expected_len)

        -- Decompress if needed
        local final_data
        if compression_mode == 1 then
          local decompressed_len = read_u32_le(payload, 1) - 8
          final_data = M.decompress(payload, 5, decompressed_len)
        elseif compression_mode == 2 then
          local decompressed_len = read_u64_le(payload, 1) - 8
          final_data = M.decompress(payload, 9, decompressed_len)
        else
          final_data = payload
        end

        -- Deserialize
        local pos_ref = { 1 }
        local result, err = M.deserialize(final_data, pos_ref)

        vim.schedule(function()
          if err then
            callback(err, nil)
          else
            callback(nil, result)
          end
        end)
      end
    end)
  end)
end

return M
