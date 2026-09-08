local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.expandtab = true
opt.termguicolors = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2

opt.ignorecase = true
opt.smartcase = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.ruler = true

-- Yank and paste through the system clipboard by default. On Linux the
-- provider is wl-copy (installed alongside Neovim by Nix); macOS and Windows
-- have theirs built in.
opt.clipboard = "unnamedplus"

-- Default to a transparent background through transparent.nvim.
vim.g.transparent_enabled = true

-- Diagnostic signs in the gutter.
vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "",
      [vim.diagnostic.severity.WARN] = "",
      [vim.diagnostic.severity.INFO] = "",
      [vim.diagnostic.severity.HINT] = "",
    },
  },
})
