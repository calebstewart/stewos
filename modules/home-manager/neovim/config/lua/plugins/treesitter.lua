-- nvim-treesitter's main branch: parsers are downloaded and built locally by
-- the tree-sitter CLI, so `tree-sitter` and a C compiler must be on PATH
-- (both from Nix; on Windows from winget, with LLVM's bin added to PATH by
-- neovim.nix). Highlighting is Neovim's own, started per buffer.
local parsers = {
  "bash",
  "c",
  "cpp",
  "go",
  "hcl",
  "java",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "nix",
  "python",
  "query",
  "regex",
  "rust",
  "toml",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install(parsers)

      -- Terraform files are HCL as far as the parser is concerned.
      vim.treesitter.language.register("hcl", { "tf", "terraform" })

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("stewos-treesitter", { clear = true }),
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },
}
