-- `:Hover zoom` and `:Hover nav` of the nvim config's BINDINGS-RUNTIME-CHECKLIST.md (task
-- hover.nvim/testblatt-bindings-checkliste), typed as the checklist names them, on a real picture: `zoom` twice writes a
-- crop per level, `nav right` moves the magnified view (a new crop), `zoom out` twice steps back to the whole picture,
-- `zoom reset` from a zoomed view goes there at once; where nothing is zoomed, `zoom reset` and `nav` say so. The
-- crops are what `hover.copy-zoom-crop` reads too: files below stdpath("cache")/hover.nvim/zoom. hover.nvim is set up as
-- the nvim config does (TESTS/sheets/_bindings.lua).
-- Like hover.copy-zoom-crop it needs images.nvim (.deps/ or beside this repository), `images.convert.crop` and an
-- ImageMagick that reads a picture in the child editor; without them the sheet is a reported skip (n/a): under
-- Windows today (MAGICK_* does not reach an rpc sheet child) and on the hosted runners. It runs in WSL.
return {
  id = "hover.bindings-zoom",
  title = "hover.nvim: the zoom and nav commands of the bindings checklist, on a real picture",
  task = "hover.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("images.nvim")]],
      reason = "images.nvim is not beside this repository",
    },
    {
      lua = [[require("hover.preview.media").can_zoom()]],
      reason = "no images.convert.crop or no ImageMagick (magick) on PATH",
    },
    {
      lua = [[(function()
        local f = vim.fn.tempname() .. ".png"
        vim.fn.system({ "magick", "-size", "4x4", "xc:red", f })
        return vim.v.shell_error == 0 and vim.uv.fs_stat(f) ~= nil
      end)()]],
      reason = "magick reads no picture in the child editor (on Windows: MAGICK_* not handed to an rpc sheet child)",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
      note = "hover.nvim as the nvim config sets it up, messages recorded",
    },
    {
      lua = [[_G.sandbox()
      local said = vim.fn.system({ "magick", "-size", "800x1200", "gradient:red-blue", "-rotate", "90", _G.root .. "/pic.png" })
      assert(vim.v.shell_error == 0, "magick could not make the picture: " .. said)
      _G.zoom_dir = vim.fn.stdpath("cache") .. "/hover.nvim/zoom"
      vim.fn.delete(_G.zoom_dir, "rf")
      _G.crops = function()
        local out = {}
        for name, kind in vim.fs.dir(_G.zoom_dir) do
          if kind == "file" then out[#out + 1] = name end
        end
        return out
      end
      vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"
      _G.open("notes.md", "see ./pic.png here")
      vim.api.nvim_win_set_cursor(0, { 1, 6 })]],
      note = "a real 1200x800 PNG, notes.md naming it, the cursor on the name",
    },
    { keys = ":Hover show<CR>", note = "the picture hover" },
    { wait = [[_G.float() ~= nil]] },
    { settle = 300 },
    { lua = [[_G.forget()]] },
    { keys = ":Hover zoom reset<CR>", note = ":Hover zoom reset with nothing zoomed" },
    { wait = [[_G.noted("nothing is zoomed")]], note = "says so" },
    { keys = ":Hover nav right<CR>", note = ":Hover nav right with nothing zoomed" },
    { wait = [[_G.noted("nothing is zoomed, so there is nothing to move")]], note = "says so" },
    { keys = ":Hover zoom<CR>", note = ":Hover zoom: in, the default" },
    { wait = [[#_G.crops() >= 1]], note = "the crop of level 1 is written" },
    { settle = 300 },
    { keys = ":Hover zoom in<CR>", note = "and once more" },
    { wait = [[#_G.crops() >= 2]], note = "the crop of level 2" },
    { settle = 300 },
    { lua = [[_G.before_nav = #_G.crops()]] },
    { keys = ":Hover nav right<CR>", note = ":Hover nav right: the magnified view moves" },
    { wait = [[#_G.crops() > _G.before_nav]], note = "a crop of another place is written" },
    { settle = 300 },
    { keys = ":Hover zoom out<CR>", note = "one level back" },
    { settle = 300 },
    { keys = ":Hover zoom out<CR>", note = "and the other" },
    { settle = 300 },
    { lua = [[_G.forget()]] },
    { keys = ":Hover zoom reset<CR>", note = "reset after two steps out" },
    {
      wait = [[_G.noted("nothing is zoomed")]],
      note = "nothing was zoomed any more: zoom out went all the way",
    },
    { keys = ":Hover zoom<CR>", note = "in again" },
    { settle = 300 },
    { lua = [[_G.forget()]] },
    { keys = ":Hover zoom reset<CR>", note = "reset from a zoomed view" },
    { settle = 300 },
    { expect = [[not _G.noted("nothing is zoomed")]], note = "it had something to reset" },
    { keys = ":Hover zoom reset<CR>", note = "and again" },
    { wait = [[_G.noted("nothing is zoomed")]], note = "the whole picture: nothing left to reset" },
    { keys = "q" },
    { wait = [[_G.float() == nil]] },
  },
  manual = {
    "In a terminal that draws pictures: :Hover zoom shows the magnified detail sharp, :Hover nav moves it the way named",
  },
}
