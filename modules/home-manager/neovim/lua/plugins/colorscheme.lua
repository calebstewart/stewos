-- The system's colour scheme, as nix-colors chose it. The palette arrives
-- through generated.lua rather than by scheme name, so a non-standard base16
-- scheme works too. Without a palette (no Nix), base16-nvim's built-in
-- catppuccin-mocha stands in.
return {
  {
    "RRethy/base16-nvim",
    lazy = false,
    priority = 1000,
    config = function()
      local platform = require("stewos.platform")
      local base16 = require("base16-colorscheme")
      if platform.palette then
        local colours = {}
        for slot, hex in pairs(platform.palette) do
          colours[slot] = "#" .. hex
        end
        base16.setup(colours)
      else
        vim.cmd.colorscheme("base16-catppuccin-mocha")
      end
    end,
  },
}
