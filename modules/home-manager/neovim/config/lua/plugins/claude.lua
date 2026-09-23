return {
  {
    -- Claude Code's IDE protocol: Claude runs in a terminal split and connects
    -- back over a local WebSocket, so it sees the current selection and proposes
    -- edits as native diffs. Sessions are Claude's own (--continue / --resume);
    -- git_repo_cwd starts it at the repository root so those see one history
    -- per project regardless of where nvim was opened.
    "coder/claudecode.nvim",
    cmd = {
      "ClaudeCode",
      "ClaudeCodeFocus",
      "ClaudeCodeSelectModel",
      "ClaudeCodeAdd",
      "ClaudeCodeSend",
      "ClaudeCodeTreeAdd",
      "ClaudeCodeStatus",
      "ClaudeCodeStart",
      "ClaudeCodeStop",
      "ClaudeCodeDiffAccept",
      "ClaudeCodeDiffDeny",
      "ClaudeCodeCloseAllDiffs",
    },
    keys = {
      -- Filetype-scoped, so it stays with the plugin rather than keymaps.lua.
      {
        "<leader>cs",
        "<cmd>ClaudeCodeTreeAdd<CR>",
        desc = "Add File to Claude",
        ft = { "neo-tree", "oil" },
      },
    },
    opts = {
      git_repo_cwd = true,
      terminal = {
        provider = "native", -- "auto" would switch to snacks.nvim if it ever appears
        split_side = "right",
        split_width_percentage = 0.35,
      },
      diff_opts = { layout = "vertical" },
    },
  },
}
