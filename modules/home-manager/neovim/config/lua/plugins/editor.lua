return {
  { "LnL7/vim-nix", ft = "nix" },
  { "moll/vim-bbye", cmd = { "Bdelete", "Bwipeout" } },

  {
    "stevearc/oil.nvim",
    lazy = false, -- the VimEnter autocmd opens it when nvim starts bare
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {},
  },

  {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
  },

  {
    "akinsho/toggleterm.nvim",
    cmd = "ToggleTerm",
    opts = {
      direction = "horizontal",
      hide_numbers = true,
    },
  },

  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    opts = {
      enable_diagnostics = true,
      enable_git_status = true,
      enable_modified_markers = true,
      enable_refresh_on_write = true,
      close_if_last_window = true,
      popup_border_style = "rounded",
      window = { mappings = { ["<space>"] = "none" } },
      filesystem = {
        filtered_items = { always_show = { ".github", ".circleci" } },
      },
    },
  },

  {
    -- Builds its preview server with npm (node comes from Nix or winget).
    -- The plugin's own mkdp#util#install helper does not survive a headless
    -- lazy install on Windows; the npm route is what lazy runs in the plugin
    -- directory on every platform.
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
    ft = "markdown",
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_browserfunc = "StewosOpenBrowser"
      -- vim.ui.open uses the platform's opener (xdg-open, open, start), so the
      -- old hard-coded firefox call is not needed.
      vim.cmd([[
        function! StewosOpenBrowser(url)
          call luaeval('vim.ui.open(_A)', a:url)
        endfunction
      ]])
    end,
  },
}
