-- StewOS Neovim. Plain Lua, shared verbatim by NixOS, nix-darwin and winpkgs.
--
-- Nix supplies two things and nothing else: the tools on PATH (language
-- servers, ripgrep, a C compiler, node) and lua/stewos/generated.lua, which
-- carries the colour palette and the per-platform server list. Nothing here
-- names a store path, so the same directory works where there is no Nix.
--
-- Layout:
--   lua/stewos/options.lua    vim.opt / vim.g
--   lua/stewos/keymaps.lua    every global mapping, grouped by which-key prefix
--   lua/stewos/autocmds.lua   autocommands
--   lua/stewos/platform.lua   generated.lua with defaults, plus OS checks
--   lua/stewos/lazy.lua       lazy.nvim bootstrap; plugin specs live in lua/plugins/

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("stewos.options")
require("stewos.keymaps")
require("stewos.autocmds")
require("stewos.lazy")
