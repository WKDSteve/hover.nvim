-- Feature hover.http-preview (the field `feature` comes with testing.nvim's feature catalog; until then only here),
-- beside the explorer: a reader of notes.md with the file tree open rests the cursor on an http link; the hover opens
-- over the note (not over the tree), fetches the page once, and shows its title and description; closing it leaves
-- the tree where it was; a second hover comes from the session cache (task hover.nvim/http-preview-live-check).
-- The network is a stub (TESTS/sheets/_helpers.lua `net_stub`): no process, no connection; the answer is data in
-- TESTS/sheets/fixtures/http/example-page.lua. The explorer is filetree.nvim on netrw (part of Neovim, no third
-- checkout); filetree.nvim comes from .deps/ (CI: ci.workflow.checkouts in .testing.lua) or beside this repository.
-- Without it the sheet is a reported skip (n/a), never green.
return {
  id = "hover.http-preview-beside-explorer",
  title = "hover.nvim: a hover over an http link beside the explorer fetches once and shows title and description",
  task = "hover.nvim/http-preview-live-check",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("filetree.nvim")]],
      reason = "filetree.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      -- No banner: it would name the temporary directory.
      vim.g.netrw_banner = 0
      _G.net_stub({ ["https://example.test/page"] = _G.fixture("example-page") })
      require("hover").setup({ links = { web = true, fetch = true } })
      -- Without its file watcher: an fs_event handle on the tree root lives for ever, so `settle` never sees the
      -- child idle; watching the folder is filetree's own concern, not this hover's.
      require("filetree").setup({ adapter = "netrw", features = { file_watcher = { enabled = false } } })]],
      note = "hover with web links and fetching on, filetree on netrw, the network a stub",
    },
    {
      lua = [[_G.sandbox()
      _G.open("notes.md", "# Notes", "", "see https://example.test/page for the details")
      vim.api.nvim_win_set_cursor(0, { 3, 10 })
      _G.note_win = vim.api.nvim_get_current_win()]],
      note = "a project with notes.md, the cursor on the link",
    },
    -- A `lua` step, not `keys = ":Lexplore<CR>"`: netrw's own `:silent! nunmap` leaves E31 ("No such mapping") in
    -- v:errmsg, which a `keys` step reads as an error of the keys (with or without filetree, with or without hover).
    { lua = [[vim.cmd.Lexplore()]], note = "the explorer on the left (:Lexplore)" },
    { wait = [[#_G.wins() == 2]], note = "tree and note side by side" },
    { lua = [[vim.api.nvim_set_current_win(_G.note_win)]], note = "back on the note" },
    { keys = ":Hover show<CR>", note = "hover the link" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    { wait = [[#_G.requests == 1]], note = "a fetch ran" },
    {
      expect = [[_G.eq(_G.requests[1].url, "https://example.test/page")]],
      note = "for the link under the cursor",
    },
    {
      wait = [[_G.float_text():find("Example Domain", 1, true) ~= nil]],
      timeout = 3000,
      note = "the page title is on the hover",
    },
    { expect = [[_G.has(_G.float_text(), "HTTP 200 OK")]], note = "and the status" },
    {
      expect = [[_G.has(_G.float_text(), "A page for the test sheets of hover.nvim.")]],
      note = "and the description",
    },
    {
      -- The float is `relative = "editor"` (hover/float.lua), so "over the note" is geometry: its left edge is at or
      -- right of the note window's, i.e. not a column of the tree is covered.
      expect = [[vim.api.nvim_win_get_position(_G.float())[2] >= vim.api.nvim_win_get_position(_G.note_win)[2]
        and vim.api.nvim_win_get_position(_G.note_win)[2] > 0]],
      note = "over the note, not over the tree on the left",
    },
    -- Up to 2 s, not 300 ms: entering the tree arms filetree's debounced redraws (lib.nvim debounce, one-shot
    -- timers), which a slow runner has not run out within 300 ms. `settle` returns as soon as they have.
    { settle = 2000 },
    { screen = "http-hover-beside-explorer" },
    { keys = "q", note = "close the hover" },
    { wait = [[_G.float() == nil]] },
    { expect = [[_G.eq(#_G.wins(), 2)]], note = "the tree is still there" },
    { keys = ":Hover show<CR>", note = "hover the same link again" },
    { wait = [[_G.float_text():find("Example Domain", 1, true) ~= nil]] },
    { expect = [[_G.eq(#_G.requests, 1)]], note = "no second fetch: the session cache answers" },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  judge = {
    "The float leads with the status line, then the title, then the description; nothing of the HTML shows",
    "The float sits over the note and does not cover the tree",
  },
  manual = {
    "Once with the real network on a real page (:Hover links web fetch on): the title arrives, nothing is sent to http://",
  },
}
