return {
  { "nvim-tree/nvim-web-devicons", lazy = true },

  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      -- One bar for the whole screen rather than one per window. With neo-tree,
      -- trouble or a Claude sidebar open, per-window bars are mostly noise, and
      -- they overwrite the blank statusline plugins use to hide their own.
      options = { globalstatus = true },
    },
  },

  {
    "xiyaowong/transparent.nvim",
    lazy = false,
    opts = {},
  },

  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {},
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>w", group = "Windows..." },
        { "<leader>b", group = "Buffers..." },
        { "<leader>o", group = "Open Tools..." },
        { "<leader>g", group = "Go to..." },
        { "<leader>f", group = "Find..." },
        { "<leader>l", group = "LSP..." },
        { "<leader>c", group = "Claude..." },
      },
    },
  },
}
