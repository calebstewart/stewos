return {
  {
    -- Claude Code through the Agent SDK: a native chat sidebar with inline
    -- permission prompts. Sessions are Claude's own (~/.claude/projects), so
    -- the CLI and this share history. Global keys live in stewos/keymaps.lua.
    "calebstewart/claude-code.nvim",
    cmd = "Claude",
    opts = {
      transport = "direct",
      window = { position = "right", size = 0.35 },
    },
  },
}
