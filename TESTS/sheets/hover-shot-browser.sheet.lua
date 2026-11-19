-- Feature hover.shot (TESTS/sheets/features.lua).
-- With `links.shot` on, `:Hover show` on an http link renders the page in a headless browser: hover starts the
-- browser named in `links.shot.command` with `--headless=new`, `--screenshot=<file in its cache>` and the link. The
-- browser is a recording stand-in (`fakes`, named `chromium`) that writes no picture, so the hover ends on "the page did
-- not render"; the sheet reads the command line it got. The child has no terminal graphics, so a stand-in `images`
-- module answers lib.nvim's provider question (a shot is only taken when a picture could be drawn). Nothing connects.
-- The lookup of an installed browser (lib.nvim.deps, no `links.shot.command`) and a real picture stay manual lines.
return {
  id = "hover.shot-browser",
  feature = "hover.shot",
  title = "hover.nvim: :Hover show on a link with shots on starts the headless browser for a screenshot of it",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  fakes = { "chromium" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      package.loaded.images = { show = function() end }
      require("hover").setup({ links = { web = true, shot = { enabled = true, command = "chromium" } } })
      _G.browsers = function()
        return require("testing.fake_programs").read(vim.env.TESTING_FAKES, "chromium")
      end
      -- The first command line as one string, `=` and `,` read as separators: the Windows stand-in (a .cmd file)
      -- splits an argument there (testing.nvim/fake-programs-der-windows-stand-in-zerlegt-argumente-am), so
      -- `--headless=new` arrives as two words there and as one elsewhere. Backslashes become slashes.
      _G.argline = function()
        return (" " .. table.concat(_G.browsers()[1].argv, " ") .. " "):gsub("[=,]", " "):gsub("\\", "/")
      end]],
      note = "hover with page shots on and a browser named outright; the browser a recording stand-in",
    },
    {
      lua = [[_G.sandbox()
      _G.open("notes.md", "# Notes", "", "see https://example.test/page for the details")
      vim.api.nvim_win_set_cursor(0, { 3, 10 })]],
      note = "a note with a link",
    },
    { keys = ":Hover show<CR>", note = "hover the link" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    { wait = [[#_G.browsers() == 1]], timeout = 5000, note = "the browser was started once" },
    {
      expect = [[_G.eq(_G.browsers()[1].argv[#_G.browsers()[1].argv], "https://example.test/page")]],
      note = "for the link under the cursor",
    },
    {
      expect = [[_G.has(_G.argline(), " --headless new ")]],
      note = "headless",
    },
    {
      expect = [[_G.argline():find(" --screenshot [^ ]*hover.nvim/shots/example.test%-[0-9a-f]+%.png ") ~= nil]],
      note = "with a screenshot file in hover's cache",
    },
    {
      wait = [[_G.float_text():find("the page did not render", 1, true) ~= nil]],
      timeout = 5000,
      note = "the stand-in drew nothing: the hover says so",
    },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  manual = {
    "Once with Chrome installed and no links.shot.command: :Hover links web shot, :Hover show on a public link shows the page",
  },
}
