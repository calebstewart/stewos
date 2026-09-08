-- What Nix decided for this machine, with defaults so the directory also works
-- copied by hand onto a machine without Nix.
--
-- lua/stewos/generated.lua is written by modules/home-manager/neovim/default.nix and
-- looks like:
--   return {
--     palette = { base00 = "1e1e2e", ... },   -- nix-colors base16, no '#'
--     servers = { "lua_ls", "gopls", ... },    -- lspconfig names to enable
--     mason = false,                           -- install servers with mason (Windows)
--   }
local ok, generated = pcall(require, "stewos.generated")
if not ok then
  generated = {}
end

local M = {}

M.windows = vim.fn.has("win32") == 1
M.mac = vim.fn.has("mac") == 1
M.linux = not M.windows and not M.mac

M.palette = generated.palette
M.servers = generated.servers or {
  "lua_ls",
  "gopls",
  "pyright",
  "clangd",
  "ts_ls",
  "rust_analyzer",
}
-- Without Nix there is nothing else to put servers on PATH.
M.mason = generated.mason
if M.mason == nil then
  M.mason = true
end

-- lspconfig name -> mason package, for the platforms that install servers
-- with mason rather than Nix.
M.mason_packages = {
  lua_ls = "lua-language-server",
  gopls = "gopls",
  nixd = "nixd",
  pyright = "pyright",
  clangd = "clangd",
  jdtls = "jdtls",
  ts_ls = "typescript-language-server",
  vala_ls = "vala-language-server",
  mesonlsp = "mesonlsp",
  qmlls = "qmlls",
  ruby_lsp = "ruby-lsp",
  rust_analyzer = "rust-analyzer",
  gh_actions_ls = "gh-actions-language-server",
}

function M.has_server(name)
  return vim.tbl_contains(M.servers, name)
end

return M
