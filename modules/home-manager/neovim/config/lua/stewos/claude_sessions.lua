-- Telescope pickers over Claude Code's own saved conversations: one resumes the
-- chosen session in claudecode.nvim's terminal, the other deletes sessions.
--
-- Claude keeps every conversation as <config>/projects/<dir>/<session-id>.jsonl,
-- where <dir> is the working directory with every non-alphanumeric character
-- replaced by '-'. Sessions are listed for the directory claudecode.nvim would
-- start Claude in (git_repo_cwd: the git root of the current file), so the
-- picker shows exactly what `claude --resume` would there.
--
-- The files are large (tens of MB per project), so titles come from ripgrep
-- matching only the small bookkeeping records, never from decoding the whole
-- transcript. Precedence follows Claude's own: a /rename title, then the
-- session name, then the generated title, then the last prompt.
local M = {}

local title_types = { "custom-title", "agent-name", "ai-title", "last-prompt" }
local title_fields = {
  ["custom-title"] = "customTitle",
  ["agent-name"] = "agentName",
  ["ai-title"] = "aiTitle",
  ["last-prompt"] = "lastPrompt",
}

local function config_dir()
  return vim.env.CLAUDE_CONFIG_DIR or vim.fs.joinpath(vim.fn.expand("~"), ".claude")
end

-- The same resolution claudecode.nvim's terminal performs with git_repo_cwd.
local function project_root()
  local file = vim.fn.expand("%:p")
  local start = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  return require("claudecode.cwd").git_root(start) or vim.fn.getcwd()
end

local function project_dir(root)
  return vim.fs.joinpath(config_dir(), "projects", (root:gsub("[^%w]", "-")))
end

---@return { id: string, path: string, title: string, prompt: string?, mtime: integer, size: integer }[]
local function list_sessions(dir)
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  local pattern = '^\\{"type":"(' .. table.concat(title_types, "|") .. ')"'
  local result = vim
    .system({
      "rg", "--no-config", "--no-heading", "--with-filename", "--null", "--no-line-number",
      "--max-depth", "1", "--glob", "*.jsonl", pattern, dir,
    }, { text = true })
    :wait()
  -- 1 is "no matches"; anything else is a real failure.
  if result.code > 1 then
    vim.notify("Listing Claude sessions failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
    return {}
  end

  -- Last record of each kind wins, per file.
  local found = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local path, json = line:match("^(%Z+)%z(.*)$")
    local ok, record = pcall(vim.json.decode, json or "")
    if path and ok and type(record) == "table" and title_fields[record.type] then
      found[path] = found[path] or {}
      found[path][record.type] = record[title_fields[record.type]]
    end
  end

  local sessions = {}
  for path, titles in pairs(found) do
    local stat = vim.uv.fs_stat(path)
    local title
    for _, kind in ipairs(title_types) do
      title = title or titles[kind]
    end
    table.insert(sessions, {
      id = vim.fn.fnamemodify(path, ":t:r"),
      path = path,
      title = (title or "(untitled)"):gsub("%s+", " "),
      prompt = titles["last-prompt"],
      mtime = stat and stat.mtime.sec or 0,
      size = stat and stat.size or 0,
    })
  end
  table.sort(sessions, function(a, b)
    return a.mtime > b.mtime
  end)
  return sessions
end

local function pick(opts)
  local root = project_root()
  local sessions = list_sessions(project_dir(root))
  if #sessions == 0 then
    vim.notify("No Claude sessions for " .. root, vim.log.levels.INFO)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = opts.title .. " (" .. vim.fn.fnamemodify(root, ":~") .. ")",
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(s)
          return {
            value = s,
            display = os.date("%Y-%m-%d %H:%M", s.mtime) .. "  " .. s.title,
            ordinal = s.title .. " " .. s.id,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Session",
        define_preview = function(self, entry)
          local s = entry.value
          local lines = {
            "Title:     " .. s.title,
            "Session:   " .. s.id,
            "Modified:  " .. os.date("%Y-%m-%d %H:%M", s.mtime),
            ("Size:      %.1f KiB"):format(s.size / 1024),
            "",
            "Last prompt:",
            "",
          }
          vim.list_extend(lines, vim.split(s.prompt or "(none)", "\n"))
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.wo[self.state.winid].wrap = true
        end,
      }),
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local picker = state.get_current_picker(bufnr)
          local chosen = vim.tbl_map(function(e)
            return e.value
          end, picker:get_multi_selection())
          if #chosen == 0 then
            local entry = state.get_selected_entry()
            chosen = entry and { entry.value } or {}
          end
          actions.close(bufnr)
          if #chosen > 0 then
            opts.on_select(chosen)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Pick a session and start Claude on it. A Claude already running in the
-- terminal is replaced -- it is saved like any other and stays resumable --
-- but only after confirming, since it may be in the middle of something.
function M.resume()
  pick({
    title = "Resume Claude Session",
    on_select = function(chosen)
      local session = chosen[1]
      local terminal = require("claudecode.terminal")
      local running = terminal.get_active_terminal_bufnr()
      if running then
        if vim.fn.confirm("Replace the running Claude session?", "&Yes\n&No", 2) ~= 1 then
          return
        end
        -- Wiping the buffer kills the job; claudecode then sees no terminal and
        -- starts a fresh one with our arguments instead of re-showing the old.
        vim.api.nvim_buf_delete(running, { force = true })
      end
      terminal.open({}, "--resume " .. session.id)
    end,
  })
end

-- Pick one or more sessions (<Tab> marks several) and delete them after
-- confirming: the transcript, its subagent transcripts and the per-session
-- state Claude keeps beside it.
function M.delete()
  pick({
    title = "Delete Claude Sessions",
    on_select = function(chosen)
      local names = vim.tbl_map(function(s)
        return "  " .. s.title
      end, chosen)
      local prompt = ("Delete %d Claude session(s)?\n%s"):format(#chosen, table.concat(names, "\n"))
      if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
        return
      end
      for _, s in ipairs(chosen) do
        for _, path in ipairs({
          s.path,
          vim.fs.joinpath(vim.fs.dirname(s.path), s.id),
          vim.fs.joinpath(config_dir(), "session-env", s.id),
          vim.fs.joinpath(config_dir(), "file-history", s.id),
        }) do
          pcall(vim.fs.rm, path, { recursive = true, force = true })
        end
      end
      vim.notify(("Deleted %d Claude session(s)"):format(#chosen), vim.log.levels.INFO)
    end,
  })
end

return M
