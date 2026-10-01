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

-- lualine already shows the mode; without this "-- INSERT --" is repeated in
-- the cmdline row underneath it (noice used to swallow it).
opt.showmode = false

-- Yank and paste through the system clipboard by default. On Linux the
-- provider is wl-copy (installed alongside Neovim by Nix); macOS and Windows
-- have theirs built in.
opt.clipboard = "unnamedplus"

-- Default to a transparent background through transparent.nvim.
vim.g.transparent_enabled = true

-- On Windows, :terminal and :! run pwsh rather than cmd.exe. :terminal gets
-- the full interactive shell, profile included; the companion options are
-- Neovim's own recipe for :! and system() (:help shell-powershell), where
-- -NoProfile and plain output keep command output clean and exit codes intact.
if require("stewos.platform").windows then
  opt.shell = "pwsh"
  opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command "
    .. "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();"
    .. "$PSDefaultParameterValues['Out-File:Encoding']='utf8';"
    .. "$PSStyle.OutputRendering='PlainText';"
    .. "Remove-Alias -Force -ErrorAction SilentlyContinue tee;"
  opt.shellredir = '2>&1 | %%{ "$_" } | Out-File %s; exit $LastExitCode'
  opt.shellpipe = '2>&1 | %%{ "$_" } | Tee-Object %s; exit $LastExitCode'
  opt.shellquote = ""
  opt.shellxquote = ""
end

-- Messages and the cmdline go through Neovim's built-in ui2 (0.12,
-- experimental) rather than noice. A message longer than 'cmdheight' is
-- collapsed with a [+N] marker instead of raising a hit-enter prompt, and g<
-- (or ENTER straight after a : command) opens it in full in a real pager
-- buffer; :messages opens there too. Deliberately not a notification popup:
-- long errors were unreadable that way. pcall so an older Neovim, which has
-- no vim._core.ui2, keeps the legacy message area instead of failing.
pcall(function()
  require("vim._core.ui2").enable({})
end)

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
