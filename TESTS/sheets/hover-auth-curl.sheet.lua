-- Feature hover.auth (TESTS/sheets/features.lua).
-- A link to a host named in `links.auth` is fetched by the real lib.nvim curl transport with the credential on stdin
-- (`-K -`), never on the command line; a link to any other host goes out without it. `curl` itself is a recording
-- stand-in (`fakes`): it answers nothing, so the hover says the fetch failed, and the sheet reads the command lines
-- the stand-in got. No connection is opened. The token is a made-up value in the child's environment only.
-- What the stand-in cannot show (the header reaching a real server) stays a manual line.
return {
  id = "hover.auth-curl",
  feature = "hover.auth",
  title = "hover.nvim: a link to a named host is fetched with its credential on stdin, never in argv, other hosts without",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  fakes = { "curl" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      vim.env.HOVER_SHEET_TOKEN = "sheet-token-0451"
      require("hover").setup({ links = { web = true, fetch = true,
        auth = { { match = "wiki.example.test", token_env = "HOVER_SHEET_TOKEN" } } } })
      _G.curls = function()
        return require("testing.fake_programs").read(vim.env.TESTING_FAKES, "curl")
      end
      _G.argv_text = function(call)
        return table.concat(call.argv, " ")
      end]],
      note = "hover with fetching on and a credential for wiki.example.test; curl is a recording stand-in",
    },
    {
      lua = [[_G.sandbox()
      _G.open("notes.md", "# Notes", "", "see https://wiki.example.test/page for it", "", "and https://other.example.test/page too")
      vim.api.nvim_win_set_cursor(0, { 3, 10 })]],
      note = "a note with a link to the named host and one to another host",
    },
    { keys = ":Hover show<CR>", note = "hover the link to the named host" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    { wait = [[#_G.curls() == 1]], timeout = 5000, note = "curl was started once" },
    {
      expect = [[_G.has(_G.argv_text(_G.curls()[1]), "https://wiki.example.test/page")]],
      note = "for the link under the cursor",
    },
    {
      expect = [[vim.tbl_contains(_G.curls()[1].argv, "-K")]],
      note = "the credential is read from stdin (-K -)",
    },
    {
      expect = [[_G.argv_text(_G.curls()[1]):find("sheet-token-0451", 1, true) == nil]],
      note = "the token is not on the command line",
    },
    { keys = "q", note = "close the hover" },
    { wait = [[_G.float() == nil]] },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 5, 10 })]],
      note = "the cursor on the link to another host",
    },
    { keys = ":Hover show<CR>", note = "hover it" },
    { wait = [[#_G.curls() == 2]], timeout = 5000, note = "a second curl" },
    {
      expect = [[_G.has(_G.argv_text(_G.curls()[2]), "https://other.example.test/page")]],
      note = "for the other link",
    },
    {
      expect = [[not vim.tbl_contains(_G.curls()[2].argv, "-K")]],
      note = "without a credential",
    },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  manual = {
    "Once against a real host of your own: the page behind the credential arrives (hover.nvim docs/FEATURES/AUTH.md)",
  },
}
