-- Language servers are enabled from the list Nix decided for this machine
-- (platform.servers) and found on PATH by executable name. On Nix platforms
-- the executables come from programs.neovim.extraPackages; on Windows mason
-- installs them.
local platform = require("stewos.platform")

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })

      vim.lsp.config("rust_analyzer", {
        -- rustc and cargo come from the project, not the editor.
        settings = { ["rust-analyzer"] = {} },
      })

      for _, server in ipairs(platform.servers) do
        vim.lsp.enable(server)
      end
    end,
  },

  {
    -- Format on save through whichever attached server can, none-ls included.
    "lukas-reineke/lsp-format.nvim",
    event = "LspAttach",
    config = function()
      local format = require("lsp-format")
      format.setup({})
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("stewos-lsp-format", { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client then
            format.on_attach(client, args.buf)
          end
        end,
      })
    end,
  },

  {
    "nvimdev/lspsaga.nvim",
    event = "LspAttach",
    dependencies = { "nvim-tree/nvim-web-devicons", "nvim-treesitter/nvim-treesitter" },
    opts = {
      ui = { devicon = true },
    },
  },

  {
    -- LSP features from external tools: nixfmt as the Nix formatter.
    "nvimtools/none-ls.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.nixfmt,
        },
      })
    end,
  },

  {
    -- Windows only (platform.mason): there is no Nix to put servers on PATH.
    "mason-org/mason.nvim",
    cond = platform.mason,
    lazy = false,
    build = ":MasonUpdate",
    config = function()
      require("mason").setup({})
      local registry = require("mason-registry")
      local wanted = {}
      for _, server in ipairs(platform.servers) do
        local pkg = platform.mason_packages[server]
        if pkg then
          table.insert(wanted, pkg)
        end
      end
      registry.refresh(function()
        for _, name in ipairs(wanted) do
          local ok, pkg = pcall(registry.get_package, name)
          if ok and not pkg:is_installed() then
            pkg:install()
          end
        end
      end)
    end,
  },
}
