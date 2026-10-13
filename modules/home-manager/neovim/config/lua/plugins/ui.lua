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
    -- A collection of small modules, each off until its table says `enabled`.
    -- Snacks wants to load first and eagerly: some modules hook startup.
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      -- Animates <C-d>/<C-u>, <C-f>/<C-b>, zz and friends, and mouse wheel
      -- scrolling. Turns itself off for terminal buffers and macro replay.
      scroll = { enabled = true },
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
        { "<leader>s", group = "Shortcut..." },
      },
    },
  },
}
