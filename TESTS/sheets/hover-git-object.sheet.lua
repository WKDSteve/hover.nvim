-- Feature hover.git-object (TESTS/sheets/features.lua).
-- A commit id in prose, asked about with `:Hover show`, shows what `git show --stat` says about it; a hex word that
-- is no object of the repository gets a sentence saying so. git runs for real against a sandbox repository (its own
-- config: no global or system config, so no signing and no hooks): `git cat-file -e` decides whether the word is an
-- object, `git show --stat` fills the float. The automatic trigger never asks git (TESTS/bare_git_spec.lua), so the
-- sheet types the command as the reader does.
return {
  id = "hover.git-object",
  feature = "hover.git-object",
  title = "hover.nvim: :Hover show on a commit id shows git show --stat, a hex word that is no object says so",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      require("hover").setup({})]],
      note = "hover with its defaults",
    },
    {
      lua = [[_G.sandbox()
      local env = { GIT_CONFIG_GLOBAL = vim.fn.has("win32") == 1 and "NUL" or "/dev/null", GIT_CONFIG_NOSYSTEM = "1",
        GIT_AUTHOR_NAME = "sheet", GIT_AUTHOR_EMAIL = "sheet@example.test",
        GIT_COMMITTER_NAME = "sheet", GIT_COMMITTER_EMAIL = "sheet@example.test",
        -- fixed dates: the same commit id on every run, so the snapshot holds
        GIT_AUTHOR_DATE = "2026-01-02T03:04:05Z", GIT_COMMITTER_DATE = "2026-01-02T03:04:05Z" }
      local function git(...)
        local res = vim.system({ "git", ... }, { cwd = _G.root, env = env, text = true }):wait()
        assert(res.code == 0, table.concat({ "git", ... }, " ") .. ": " .. (res.stderr or ""))
        return vim.trim(res.stdout or "")
      end
      vim.fn.writefile({ "# Resolver", "", "resolves the links" }, _G.root .. "/resolver.md")
      git("init", "-q")
      git("add", "resolver.md")
      git("commit", "-q", "-m", "resolver: first notes")
      _G.sha = git("rev-parse", "--short=9", "HEAD")
      _G.open("log.md", "# Log", "", "fixed in " .. _G.sha .. " yesterday", "", "not an object: deadbeef42 here")
      vim.api.nvim_win_set_cursor(0, { 3, 12 })]],
      note = "a repository with one commit, a log that names it; the cursor on the commit id",
    },
    { keys = ":Hover show<CR>", note = "ask about the commit id" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    {
      wait = [[_G.float_text():find("resolver: first notes", 1, true) ~= nil]],
      timeout = 5000,
      note = "git show answers with the commit message",
    },
    {
      expect = [[_G.has(_G.float_text(), "resolver.md")]],
      note = "and the file it touched (--stat)",
    },
    {
      expect = [[_G.has(_G.float_text(), "1 file changed")]],
      note = "with the summary line",
    },
    { settle = 300 },
    { screen = "git-object" },
    { keys = "q", note = "close the hover" },
    { wait = [[_G.float() == nil]], note = "the float is gone" },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 5, 17 })]],
      note = "the cursor on a hex word that is no object",
    },
    { keys = ":Hover show<CR>", note = "ask about it" },
    {
      wait = [[_G.float_text():find("no such object", 1, true) ~= nil]],
      timeout = 5000,
      note = "the float says there is no such object",
    },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  judge = {
    "The commit float reads as git show --stat: the id, the author, the message, the file and the summary line",
  },
}
