return {
  { "nvim-tree/nvim-web-devicons", lazy = true },

  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {},
  },

  {
    "xiyaowong/transparent.nvim",
    lazy = false,
    opts = {},
  },

  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
    opts = {
      presets = { bottom_search = true },
    },
  },

  {
    -- Fancy notifications within neovim. NOTE: british spelling :sob:
    "rcarriga/nvim-notify",
    lazy = true,
    opts = function()
      local platform = require("stewos.platform")
      return {
        background_colour = platform.palette and ("#" .. platform.palette.base01) or "#000000",
      }
    end,
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
      },
    },
  },
}
