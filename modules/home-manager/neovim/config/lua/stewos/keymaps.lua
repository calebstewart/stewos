-- Every global mapping. Plugin-local mappings (buffer-scoped, or set by a
-- plugin's own setup) stay with the plugin spec.
local map = function(lhs, rhs, desc, mode)
  vim.keymap.set(mode or "n", lhs, rhs, { desc = desc, silent = true })
end

-- <leader>f  Find...
map("<leader>ff", "<cmd>Telescope find_files<CR>", "Find Project File")
map("<leader>fs", "<cmd>Telescope live_grep<CR>", "Search All Files")
map("<leader>fi", "<cmd>Telescope lsp_incoming_calls<CR>", "Find Incoming Calls")
map("<leader>fo", "<cmd>Telescope lsp_outgoing_calls<CR>", "Find Outgoing Calls")
map("<leader>fr", "<cmd>Telescope lsp_references<CR>", "Find References")

-- <leader>g  Go to...
map("<leader>gd", "<cmd>Telescope lsp_definitions<CR>", "Go to Definition")
map("<leader>gt", "<cmd>Telescope lsp_type_definitions<CR>", "Go to Type Definition")
map("<leader>gi", "<cmd>Telescope lsp_implementations<CR>", "Go to Implementation")

-- <leader>o  Open Tools...
map("<leader>of", "<cmd>Neotree toggle<CR>", "Toggle NeoTree Explorer")
map("<leader>ot", "<cmd>ToggleTerm<CR>", "Toggle Terminal")
map("<leader>og", "<cmd>Neogit<CR>", "Open Neogit")

-- <leader>b  Buffers...
map("<leader>bb", "<cmd>Telescope buffers<CR>", "Show Open Buffers")
map("<leader>bd", "<cmd>Bwipeout<CR>", "Close Current Buffer")
map("<leader>bK", "<cmd>bufdo :Bwipeout<CR>", "Close All Buffers")
map("<leader>bh", "<cmd>bprevious<CR>", "Switch to Previous Buffer")
map("<leader>bl", "<cmd>bnext<CR>", "Switch to Next Buffer")
map("<leader>bk", "<cmd>b#<CR>", "Toggle Between Recent Buffers")
map("<leader>bj", "<cmd>b#<CR>", "Toggle Between Recent Buffers")

-- <leader>w  Windows...
map("<leader>wsh", "<cmd>split<CR>", "Split Window - Horizontal")
map("<leader>wsv", "<cmd>vsplit<CR>", "Split Window - Vertical")
map("<leader>wd", "<cmd>close<CR>", "Close Window")
map("<leader>wx", "<cmd>only<CR>", "Close ALL OTHER Windows")
map("<leader>ww", "<C-w>w", "Switch Windows")
map("<leader>wh", "<cmd>wincmd h<CR>", "Focus Window Left")
map("<leader>wj", "<cmd>wincmd j<CR>", "Focus Window Down")
map("<leader>wk", "<cmd>wincmd k<CR>", "Focus Window Up")
map("<leader>wl", "<cmd>wincmd l<CR>", "Focus Window Right")

-- <leader>l  LSP...
-- The nixvim configuration bound <leader>lr twice (LspRestart, then rename);
-- rename won. Restart moved to <leader>lR so both exist.
map("<leader>lx", "<cmd>LspStop<CR>", "Stop LSP Server")
map("<leader>ls", "<cmd>LspStart<CR>", "Start LSP Server")
map("<leader>lR", "<cmd>LspRestart<CR>", "Restart LSP Server")
map("<leader>lr", function() vim.lsp.buf.rename() end, "Rename Current Symbol")
map("<leader>ll", "<cmd>Lspsaga show_line_diagnostics<CR>", "Show Line Diagnostics")
map("<leader>la", "<cmd>Lspsaga code_action<CR>", "View Code Actions")
map("K", "<cmd>Lspsaga hover_doc<CR>", "Hover Documentation")
