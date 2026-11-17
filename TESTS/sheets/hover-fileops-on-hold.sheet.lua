-- Feature hover.contributions (TESTS/sheets/features.lua), the collision half: hover.nvim and fileops.nvim's `on_hold`
-- both answer CursorHold in the same buffer. A reader rests the cursor on a link in a note whose line they changed
-- and have not saved; hover opens its float for the link, fileops shows the committed version of the line as virtual
-- text at its end ("previous: ..."). Measured here: what each one draws (fileops draws no float, only an extmark),
-- whether the float covers that text, whether one takes the other away, and what fileops does to 'updatetime'.
-- fileops is set up with its defaults (`delay = 3000` on top of 'updatetime', `throttle_ms = 1200`), gitsigns is not
-- installed, so `on_hold` takes its own path (`git blame` + `git show`, real processes against a sandbox repository).
-- Task: hover.nvim/sheet-hover-neben-fileops-on-hold (out of the live round hover.nvim/copy-live-check). fileops.nvim
-- comes from .deps/ (CI: ci.workflow.checkouts in .testing.lua) or beside this repository; without it the sheet is a
-- reported skip (n/a).
return {
  id = "hover.fileops-on-hold",
  feature = "hover.contributions",
  title = "hover.nvim beside fileops.nvim on_hold: one float and one line of virtual text from the same CursorHold",
  task = "hover.nvim/copy-live-check",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("fileops.nvim")]],
      reason = "fileops.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      -- as in a real config: hover attaches its CursorHold to a buffer on FileType
      vim.cmd("filetype on")
      _G.updatetime_before = vim.o.updatetime
      require("fileops").setup({ keymaps = false, on_hold = { enable = true } })
      -- enable(), not setup(): only enable() installs the trigger autocmds (lua/hover/init.lua `M.enable`)
      require("hover").enable({ auto_hover = true })]],
      note = "fileops with on_hold on (its defaults otherwise), hover on CursorHold for every target type",
    },
    {
      expect = [[_G.eq(vim.o.updatetime, 100)]],
      note = "fileops lowered the default 'updatetime' to 100 for the whole editor: hover's CursorHold follows it too",
    },
    {
      lua = [[_G.sandbox()
      -- A repository of its own: no global or system git config (no signing, no hooks), an author for the commit.
      local env = { GIT_CONFIG_GLOBAL = vim.fn.has("win32") == 1 and "NUL" or "/dev/null", GIT_CONFIG_NOSYSTEM = "1",
        GIT_AUTHOR_NAME = "sheet", GIT_AUTHOR_EMAIL = "sheet@example.test",
        GIT_COMMITTER_NAME = "sheet", GIT_COMMITTER_EMAIL = "sheet@example.test" }
      local function git(...)
        local res = vim.system({ "git", ... }, { cwd = _G.root, env = env, text = true }):wait()
        assert(res.code == 0, table.concat({ "git", ... }, " ") .. ": " .. (res.stderr or ""))
      end
      vim.fn.writefile({ "# Other", "", "the other note" }, _G.root .. "/other.md")
      vim.fn.writefile({ "# Notes", "", "see [the other note](other.md) for details" }, _G.root .. "/notes.md")
      git("init", "-q")
      git("add", "other.md", "notes.md")
      git("commit", "-q", "-m", "notes")
      vim.cmd("edit! " .. vim.fn.fnameescape(_G.root .. "/notes.md"))
      vim.api.nvim_buf_set_lines(0, 2, 3, false, { "see [the other note](other.md) for more" })
      _G.ns = vim.api.nvim_create_namespace("fileops_on_hold_preview")
      _G.marks = function()
        return vim.api.nvim_buf_get_extmarks(0, _G.ns, 0, -1, { details = true })
      end]],
      note = "a repository with notes.md committed; line 3 changed in the buffer and not saved",
    },
    {
      keys = "3G0f[l",
      note = "the cursor onto the link, then nothing typed: CursorHold for both plugins",
    },
    { wait = [[_G.float() ~= nil]], timeout = 3000, note = "hover's float is up" },
    {
      lua = [[_G.t_float = vim.uv.hrtime()]],
      note = "when the float came",
    },
    { expect = [[_G.has(_G.float_text(), "the other note")]], note = "it previews other.md" },
    {
      expect = [[_G.eq(#_G.marks(), 0)]],
      note = "fileops has drawn nothing yet: its 3 s delay runs",
    },
    {
      wait = [[#_G.marks() > 0]],
      timeout = 10000,
      note = "fileops' preview arrives (after git blame and git show)",
    },
    {
      lua = [[_G.t_marks = vim.uv.hrtime()]],
      note = "when the virtual text came",
    },
    {
      -- Both times are taken when a poll saw the thing, so on a loaded machine the float can be seen late and the
      -- gap look shorter than fileops' 3 s; more than a second still says what matters.
      expect = [[(_G.t_marks - _G.t_float) / 1e6 > 1000]],
      note = "well after hover (fileops' delay is 3 s): the two never appear together, hover first",
    },
    {
      expect = [[_G.has(_G.marks()[1][4].virt_text[1][1], "previous: see [the other note](other.md) for details")]],
      note = "the committed line, at the end of line 3",
    },
    { expect = [[_G.eq(_G.marks()[1][2], 2)]], note = "on the cursor line" },
    {
      expect = [[_G.float() ~= nil]],
      note = "hover's float is still there: fileops does not take it away",
    },
    {
      expect = [[_G.eq(#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end,
        vim.api.nvim_list_wins()), 1)]],
      note = "one float on the screen: fileops opened none",
    },
    {
      expect = [[vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 5 })]],
      note = "the cursor stayed where it rested",
    },
    { settle = 2000 },
    {
      expect = [[(function()
        local row = vim.fn.screenpos(0, 3, 1).row
        local cells = {}
        for col = 1, vim.o.columns do cells[#cells + 1] = vim.fn.screenstring(row, col) end
        return table.concat(cells):find("previous: see [the other note]", 1, true) ~= nil
      end)()]],
      note = "the float does not cover the virtual text: it reads on screen, on the cursor's row",
    },
    { screen = "float-and-previous-line" },
    { keys = "k", note = "the cursor moves on (a line up: line 3 is the last)" },
    { wait = [[_G.float() == nil]], note = "hover's float is gone" },
    { wait = [[#_G.marks() == 0]], note = "and fileops' virtual text with it" },
  },
  judge = {
    "The float sits below the cursor line; the previous-line text at the end of line 3 stays readable beside the link",
  },
  manual = {
    "A working day with fileops on_hold.enable = true and hover.nvim on CursorHold in the real config: does anything flicker, and is 'updatetime' = 100 (fileops lowers the default for everyone) a problem for other plugins",
    "With gitsigns installed: on_hold uses preview_hunk_inline instead, which inserts lines and restores the view; check whether hover's float jumps or closes then",
  },
}
