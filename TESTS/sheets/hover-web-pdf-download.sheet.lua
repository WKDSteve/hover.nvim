-- Feature hover.web-pdf (TESTS/sheets/features.lua).
-- A link whose page fetch answers with a PDF (`content-type: application/pdf`) is downloaded with curl into hover's
-- cache, so its first page can be shown. The page fetch is the network stub of TESTS/sheets/_helpers.lua
-- (`net_stub`); the download is hover's own `curl -o` and runs against a recording stand-in (`fakes`) that writes
-- nothing, so the hover ends on "the document did not download". The sheet reads the command line curl got: the link,
-- the PDF Accept header, an output file, `--globoff`. Rasterizing a real document (pdftoppm, an image provider) stays a
-- manual line.
return {
  id = "hover.web-pdf-download",
  feature = "hover.web-pdf",
  title = "hover.nvim: a link that answers with a PDF is downloaded with curl -o, a failed download is said",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  fakes = { "curl" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      _G.net_stub({ ["https://example.test/report.pdf"] = _G.fixture("pdf-document") })
      require("hover").setup({ links = { web = true, fetch = true, pdf = { enabled = true } } })
      _G.curls = function()
        return require("testing.fake_programs").read(vim.env.TESTING_FAKES, "curl")
      end]],
      note = "hover with fetching and PDF links on; the page fetch a stub, curl a recording stand-in",
    },
    {
      lua = [[_G.sandbox()
      _G.open("notes.md", "# Notes", "", "the report is https://example.test/report.pdf here")
      vim.api.nvim_win_set_cursor(0, { 3, 16 })]],
      note = "a note with a link to a PDF",
    },
    { keys = ":Hover show<CR>", note = "hover the link" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    { wait = [[#_G.requests == 1]], note = "the page fetch ran (stub)" },
    { wait = [[#_G.curls() == 1]], timeout = 5000, note = "and then one download" },
    {
      expect = [[_G.eq(_G.curls()[1].argv[#_G.curls()[1].argv], "https://example.test/report.pdf")]],
      note = "of the link under the cursor",
    },
    {
      expect = [[vim.tbl_contains(_G.curls()[1].argv, "-o") and vim.tbl_contains(_G.curls()[1].argv, "--globoff")]],
      note = "into a file, with globbing off",
    },
    {
      expect = [[vim.tbl_contains(_G.curls()[1].argv, "Accept: application/pdf")]],
      note = "asking for the PDF",
    },
    {
      wait = [[_G.float_text():find("the document did not download", 1, true) ~= nil]],
      timeout = 5000,
      note = "the stand-in wrote nothing: the hover says so",
    },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  manual = {
    "Once with the real network: a link to a public PDF shows its first page (pdftoppm and an image provider needed)",
  },
}
