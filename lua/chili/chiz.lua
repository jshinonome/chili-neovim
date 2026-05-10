--- Chiz language server integration for chili.nvim.
--- Sets up the chili language server, completion, document highlight,
--- keymaps, and format-on-save for chi/pep filetypes.
local M = {}

--- Reference to plugin opts (set via set_opts)
local opts = {}

--- The LSP client name used to filter LspAttach events.
local CLIENT_NAME = "chili language server"

--- Set the plugin options reference.
---@param o table
function M.set_opts(o)
  opts = o
end

--- Setup nvim-cmp completion for chi/pep filetypes only.
--- Scoped via cmp.setup.filetype() to avoid overwriting user's global cmp config.
function M.setup_cmp()
  local ok, cmp = pcall(require, "cmp")
  if not ok then
    return
  end

  local cmp_opts = opts.cmp or {}
  local lsp_opts = opts.lsp or {}
  local filetypes = lsp_opts.filetypes or { "chi", "pep" }

  local filetype_config = {
    sources = cmp.config.sources({
      { name = "nvim_lsp" },
      { name = "vsnip" },
      { name = "buffer" },
    }),
    window = {
      completion = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      ["<C-b>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.abort(),
      ["<CR>"] = cmp.mapping.confirm({ select = true }),
    }),
    completion = {
      keyword_length = cmp_opts.keyword_length or 2,
    },
  }

  for _, ft in ipairs(filetypes) do
    cmp.setup.filetype(ft, filetype_config)
  end
end

--- Start the chili language server for chi/pep filetypes.
function M.setup_lsp_server()
  local lsp_opts = opts.lsp or {}
  local cmd = lsp_opts.cmd or { "chiz", "server" }
  local filetypes = lsp_opts.filetypes or { "chi", "pep" }

  -- Create augroup once, outside the callback, with clear = false so
  -- buffers don't clobber each other's autocmds.
  local hl_group = lsp_opts.document_highlight ~= false
      and vim.api.nvim_create_augroup("ChiliLSPDocumentHighlight", { clear = false })
    or nil

  vim.api.nvim_create_autocmd("FileType", {
    pattern = filetypes,
    callback = function()
      local found = vim.fs.find({ "src" }, { upward = true })
      local root_dir = found[1] and vim.fs.dirname(found[1]) or vim.fn.getcwd()

      vim.lsp.start({
        name = CLIENT_NAME,
        cmd = cmd,
        filetypes = filetypes,
        root_dir = root_dir,
      })

      -- Document highlight on cursor hold (per-buffer autocmds)
      if hl_group then
        vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
          buffer = 0,
          group = hl_group,
          callback = function()
            vim.lsp.buf.document_highlight()
          end,
        })
        vim.api.nvim_create_autocmd({ "CursorMoved" }, {
          buffer = 0,
          group = hl_group,
          callback = function()
            vim.lsp.buf.clear_references()
          end,
        })
      end
    end,
  })
end

--- Setup LSP keymaps on LspAttach, scoped to the chili language server only.
function M.setup_lsp_keymaps()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("ChiliLspKeymaps", {}),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= CLIENT_NAME then
        return
      end

      vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
      local buf_opts = { buffer = ev.buf }
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, buf_opts)
      vim.keymap.set("n", "gr", vim.lsp.buf.references, buf_opts)
      vim.keymap.set("n", "K", vim.lsp.buf.hover, buf_opts)
      vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, buf_opts)
      vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, buf_opts)
      vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, buf_opts)
      vim.keymap.set("n", "<space>wl", function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
      end, buf_opts)
      vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, buf_opts)
      vim.keymap.set("n", "<space>f", function()
        vim.lsp.buf.format({ async = true })
      end, buf_opts)
    end,
  })
end

--- Setup format-on-save via BufWritePre, scoped to chi/pep filetypes.
function M.setup_format_on_save()
  local lsp_opts = opts.lsp or {}
  if lsp_opts.format_on_save == false then
    return
  end

  local filetypes = lsp_opts.filetypes or { "chi", "pep" }
  local ft_set = {}
  for _, ft in ipairs(filetypes) do
    ft_set[ft] = true
  end

  local group = vim.api.nvim_create_augroup("ChiliLspFormatting", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = function()
      if ft_set[vim.bo.filetype] then
        vim.lsp.buf.format({ async = false })
      end
    end,
  })
end

--- Main setup entry point. Called from init.lua.
function M.setup()
  local lsp_opts = opts.lsp or {}
  local cmd = lsp_opts.cmd or { "chiz", "server" }

  if vim.fn.executable(cmd[1]) ~= 1 then
    vim.notify(
      string.format(
        "[chili.nvim] '%s' not found on $PATH.\n"
          .. "Install it with: pip install chiz\n"
          .. "https://pypi.org/project/chiz/",
        cmd[1]
      ),
      vim.log.levels.WARN
    )
    return
  end

  M.setup_cmp()
  M.setup_lsp_server()
  M.setup_lsp_keymaps()
  M.setup_format_on_save()
end

return M
