return {
  {
    -- Shortcut stories and epics as Markdown buffers: `:e sc-123`, edit, `:w`.
    -- The token comes from the `short` CLI's config (huntress-mbp installs it),
    -- or `:Shortcut login` writes that file. Loaded at startup on purpose:
    -- `:e sc-<id>`, `gf` and pasted links only work if the plugin is loaded
    -- before the buffer is opened. Global keys live in stewos/keymaps.lua.
    "calebstewart/shortcut.nvim",
    lazy = false,
    dependencies = { "folke/snacks.nvim" },
    opts = {},
  },
}
