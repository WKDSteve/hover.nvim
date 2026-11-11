-- Feature hover.http-preview (TESTS/sheets/features.lua).
-- Live check: a hover over an http link fetches the page once and shows its status, title and description
-- (task hover.nvim/http-preview-live-check).
-- Automated: in notes.md the cursor rests on an https link; `:Hover show` opens a float over the note, exactly one
-- request goes out for that link, and the float leads with "HTTP 200 OK", then the page title, then its description,
-- with nothing of the HTML; a second hover of the same link comes from the session cache (no second request); a
-- link that answers 404 shows the status as the answer.
-- The network is a stub (TESTS/sheets/_helpers.lua `net_stub`): no process, no connection, the guard stays strict;
-- the answers are data in TESTS/sheets/fixtures/http/. The real transport stays by hand (`manual`).
return {
  id = "hover.http-preview-alone",
  feature = "hover.http-preview",
  title = "hover.nvim: a hover over an http link fetches once and shows status, title and description",
  task = "hover.nvim/http-preview-live-check",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      _G.net_stub({
        ["https://example.test/page"] = _G.fixture("example-page"),
        ["https://example.test/gone"] = _G.fixture("missing-page"),
      })
      require("hover").setup({ links = { web = true, fetch = true } })]],
      note = "hover with web links and fetching on, the network a stub",
    },
    {
      lua = [[_G.sandbox()
      _G.open("notes.md", "# Notes", "", "see https://example.test/page for the details", "", "old https://example.test/gone link")
      vim.api.nvim_win_set_cursor(0, { 3, 10 })
      _G.note_win = vim.api.nvim_get_current_win()]],
      note = "a project with notes.md, the cursor on the first link",
    },
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
      note = "the page title arrives on the hover",
    },
    {
      expect = [[_G.has(_G.float_text(), "HTTP 200 OK")]],
      note = "the status line",
    },
    {
      expect = [[_G.has(_G.float_text(), "A page for the test sheets of hover.nvim.")]],
      note = "the description",
    },
    {
      expect = [[_G.float_text():find("HTTP 200 OK", 1, true) < _G.float_text():find("Example Domain", 1, true)]],
      note = "the status comes before the title",
    },
    {
      expect = [[_G.float_text():find("<", 1, true) == nil]],
      note = "nothing of the HTML shows",
    },
    { expect = [[#_G.requests == 1]], note = "exactly one fetch" },
    { settle = 300 },
    { screen = "http-hover" },
    { keys = "q", note = "close the hover" },
    { wait = [[_G.float() == nil]], note = "the float is gone" },
    { keys = ":Hover show<CR>", note = "hover the same link again" },
    { wait = [[_G.float_text():find("Example Domain", 1, true) ~= nil]], note = "the same page" },
    { expect = [[_G.eq(#_G.requests, 1)]], note = "no second fetch: the session cache answers" },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 5, 8 })]],
      note = "the cursor on the link that is gone",
    },
    { keys = ":Hover show<CR>", note = "hover it" },
    { wait = [[#_G.requests == 2]], note = "a fetch for this link" },
    { expect = [[_G.eq(_G.requests[2].url, "https://example.test/gone")]] },
    {
      wait = [[_G.float_text():find("HTTP 404 Not Found", 1, true) ~= nil]],
      timeout = 3000,
      note = "the float says the page is gone",
    },
    { settle = 300 },
    { screen = "http-hover-404" },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  judge = {
    "The float leads with the status line, then the title, then the description; nothing of the HTML shows",
    "The 404 float reads as an error (its own highlight), not as a page",
  },
  manual = {
    "Once with the real network on a real page (:Hover links web fetch on): the title arrives, nothing is sent to http://",
  },
}
