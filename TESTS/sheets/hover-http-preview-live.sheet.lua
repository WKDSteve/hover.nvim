-- Live sheet: the hand line of hover.http-preview-alone ("once with the real network on a real page") with the real
-- network (task hover.nvim/http-preview-live-check).
-- Automated, against https://example.com/ (a page kept for exactly this, title "Example Domain"):
--   * with web links and fetching on, a hover over the https link runs the real curl and the page title arrives;
--   * a credential rule names example.com (its token a dummy the child sets itself); over https it would apply
--     (`hover.auth.for_url`), but a hover over the http:// link of the same path sends nothing of it: no
--     `bearer_token` in the request, no `-K` and no stdin config for curl, no "Authorization" in its argv.
--     The https request with the rule is never made: the dummy token reaches no server.
-- Every curl the child starts is recorded by a wrapper around vim.system that hands it on unchanged, so the
-- transport and the network guard of the live sheet stay real.
-- Runs only with `testing sheets run --live`; in the suite, without --live and under CI it is a reported skip
-- (testing.nvim docs/SHEETS.md, "Live sheets"). No feature: a feature sheet may not skip under CI.
-- No live.env: the http preview needs no key, only the network (testing.nvim allows a live sheet without variables).
return {
  id = "hover.http-preview-live",
  title = "hover.nvim: with the real network the title of a real page arrives, and http:// gets no credential",
  task = "hover.nvim/http-preview-live-check",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  live = {
    hosts = { "example.com" },
    cost = "two GET requests to example.com, no key",
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      _G.curls = {}
      local system = vim.system
      vim.system = function(cmd, opts, on_exit)
        if type(cmd) == "table" and type(cmd[1]) == "string" and vim.fs.basename(cmd[1]):match("^curl") then
          _G.curls[#_G.curls + 1] = { argv = vim.deepcopy(cmd), stdin = opts and opts.stdin }
        end
        return system(cmd, opts, on_exit)
      end
      vim.env.HOVER_LIVE_SHEET_TOKEN = "dummy-token-of-the-live-sheet"
      require("hover").setup({
        links = {
          web = true,
          fetch = true,
          timeout_ms = 15000,
          auth = { { match = "example.com/private/*", token_env = "HOVER_LIVE_SHEET_TOKEN" } },
        },
      })]],
      note = "hover with web links and fetching on, a credential rule for example.com/private/*, curl recorded",
    },
    {
      expect = [[require("hover.auth").for_url("https://example.com/private/page") ~= nil]],
      note = "over https the rule would hand on the token (nothing is fetched here)",
    },
    {
      expect = [[require("hover.auth").for_url("http://example.com/private/page") == nil]],
      note = "over http it hands on nothing",
    },
    {
      lua = [[_G.sandbox()
      _G.open("notes.md", "# Notes", "", "see https://example.com/ for the page", "",
        "and http://example.com/private/page plain")
      vim.api.nvim_win_set_cursor(0, { 3, 10 })]],
      note = "a project with notes.md, the cursor on the https link",
    },
    { keys = ":Hover show<CR>", note = "hover the https link" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    {
      wait = [[_G.float_text():find("Example Domain", 1, true) ~= nil]],
      timeout = 20000,
      note = "the title of the real page arrives",
    },
    { expect = [[_G.has(_G.float_text(), "HTTP 200")]], note = "with its status" },
    { expect = [[_G.eq(#_G.curls, 1)]], note = "one real curl ran" },
    {
      expect = [[vim.tbl_contains(_G.curls[1].argv, "https://example.com/")]],
      note = "for the link under the cursor",
    },
    { keys = "q", note = "close the hover" },
    { wait = [[_G.float() == nil]] },
    {
      lua = [[vim.api.nvim_win_set_cursor(0, { 5, 10 })]],
      note = "the cursor on the http:// link under the rule's path",
    },
    { keys = ":Hover show<CR>", note = "hover it" },
    { wait = [[#_G.curls == 2]], timeout = 5000, note = "a real curl for it" },
    {
      expect = [[vim.tbl_contains(_G.curls[2].argv, "http://example.com/private/page")]],
      note = "for the http:// link",
    },
    {
      expect = [[_G.curls[2].stdin == nil or not tostring(_G.curls[2].stdin):find("dummy-token", 1, true)]],
      note = "no credential config on curl's stdin",
    },
    {
      expect = [[not vim.tbl_contains(_G.curls[2].argv, "-K")]],
      note = "curl reads no config with a credential",
    },
    {
      expect = [[not table.concat(_G.curls[2].argv, " "):lower():find("authorization", 1, true)
        and not table.concat(_G.curls[2].argv, " "):find("dummy-token", 1, true)]],
      note = "no Authorization header and no token in its argv",
    },
    {
      wait = [[_G.float_text():find("HTTP %d") ~= nil]],
      timeout = 20000,
      note = "the answer of the real host shows (whatever its status)",
    },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
}
