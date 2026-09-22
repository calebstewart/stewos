local group = vim.api.nvim_create_augroup("stewos", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = group,
  pattern = "*.md",
  desc = "Setup Markdown-Specific Keymaps",
  callback = function()
    vim.schedule(function()
      vim.keymap.set("n", "<leader>op", "<cmd>MarkdownPreview<CR>", { buffer = true, desc = "Markdown Preview" })
    end)
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  pattern = "*",
  desc = "Open current directory if no argument is given",
  callback = function()
    if vim.fn.argc() == 0 then
      vim.cmd("Oil")
    end
  end,
})

-- Illuminate highlights follow Visual, whatever the colour scheme.
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  pattern = "*",
  callback = function()
    for _, name in ipairs({ "IlluminatedWordText", "IlluminatedWordRead", "IlluminatedWordWrite" }) do
      vim.api.nvim_set_hl(0, name, { link = "Visual" })
    end
  end,
})
