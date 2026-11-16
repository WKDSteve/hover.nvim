-- Live check: `:Hover copy` / `Y`, the picture part (task hover.nvim/copy-live-check, point "Image hover, > twice,
-- move with l, Y"). A picture hover is zoomed in twice with `>` and moved right with `l`; `Y` then copies the crop on
-- screen, not the whole picture: the file named in the register lies under stdpath("cache")/hover.nvim/copies, its
-- PNG size (read from IHDR) is the rectangle of zoom level 2, smaller than the source, and its pixels are those of the
-- moved crop, not of the centred one. The picture is made by the same ImageMagick the crop runs (no binary fixture),
-- 1200x800 with a gradient from left to right, so a crop moved sideways differs from the centred one.
-- images.nvim comes from .deps/ or beside this repository ($IMAGES_NVIM_DIR, named in TESTS/minimal_init.lua); without
-- it, without `images.convert.crop` and ImageMagick on PATH, or with a magick that reads no picture in the child, the
-- sheet is a reported skip (n/a), not red. The clipboard is stubbed as in
-- hover.copy-register; the real clipboard, a PDF page and a page screenshot stay by hand.
return {
  id = "hover.copy-zoom-crop",
  feature = "hover.copy",
  title = "hover.nvim: Y after a zoom copies the crop on screen, not the whole picture",
  task = "hover.nvim/copy-live-check",
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
      -- On Windows a scoop or portable ImageMagick finds its coders only through MAGICK_HOME and friends, and the
      -- child of an rpc sheet does not get them (env_allow of .testing.lua reaches the spec children only): there
      -- magick starts and reads nothing. A picture of 4x4 pixels tells, instead of a red step further down.
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
      vim.o.laststatus = 0; vim.o.ruler = false
      package.loaded["lib.nvim.cross.copy_to_clipboard"] = function(text)
        _G.clipped = _G.clipped or {}
        _G.clipped[#_G.clipped + 1] = text
        return true
      end
      require("hover").setup({})]],
      note = "hover.nvim with its defaults; the system clipboard stubbed",
    },
    {
      lua = [[_G.sandbox()
      _G.media = require("hover.preview.media")
      local said = vim.fn.system({ "magick", "-size", "800x1200", "gradient:red-blue", "-rotate", "90", _G.root .. "/pic.png" })
      assert(vim.v.shell_error == 0, "magick could not make the picture: " .. said)
      _G.source = assert(_G.media.pixel_size(_G.root .. "/pic.png"))
      _G.zoom_dir = vim.fn.stdpath("cache") .. "/hover.nvim/zoom"
      vim.fn.delete(_G.zoom_dir, "rf")
      _G.crops = function()
        local out = {}
        for name, kind in vim.fs.dir(_G.zoom_dir) do
          if kind == "file" then out[#out + 1] = _G.zoom_dir .. "/" .. name end
        end
        return out
      end
      _G.bytes = function(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
      end
      vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"
      _G.open("notes.md", "see ./pic.png here")
      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      vim.fn.setreg('"', "")]],
      note = "a real 1200x800 PNG (gradient left to right), notes.md naming it, the cursor on the name",
    },
    {
      expect = [[_G.source.width == 1200 and _G.source.height == 800]],
      note = "the source has the size it was made with",
    },
    { keys = ":Hover show<CR>", note = "open the picture hover" },
    { wait = [[_G.float() ~= nil]], note = "the float is up" },
    { settle = 300 },
    { keys = ">", note = "zoom in once" },
    { wait = [[#_G.crops() >= 1]], note = "the first crop is written" },
    { settle = 300 },
    { keys = ">", note = "zoom in again" },
    { wait = [[#_G.crops() >= 2]], note = "the crop of level 2 is written" },
    { settle = 300 },
    { lua = [[_G.centred = vim.deepcopy(_G.crops())]] },
    { keys = "l", note = "move the zoomed view right" },
    { wait = [[#_G.crops() >= 3]], note = "the moved crop is written" },
    { settle = 500 },
    { keys = "Y", note = "copy what the hover shows" },
    {
      wait = [[vim.fn.getreg('"') ~= ""]],
      note = "the register holds a path",
    },
    {
      lua = [[_G.copied = vim.fn.getreg('"')
      local moved
      for _, p in ipairs(_G.crops()) do
        if not vim.tbl_contains(_G.centred, p) then moved = p end
      end
      _G.moved = moved
      _G.copy_px = _G.media.pixel_size(_G.copied)
      _G.want = _G.media.zoom_rect(_G.source, 2, 0.5, 0.5)]],
    },
    {
      expect = [[vim.fs.normalize(vim.fs.dirname(_G.copied))
        == vim.fs.normalize(vim.fn.stdpath("cache") .. "/hover.nvim/copies")]],
      note = "the copy lies under stdpath('cache')/hover.nvim/copies",
    },
    {
      expect = [[vim.fn.getregtype('"') == "v" and _G.clipped and _G.clipped[#_G.clipped] == _G.copied]],
      note = "the path went charwise into the register and to the clipboard",
    },
    {
      expect = [[_G.copy_px and _G.copy_px.width < _G.source.width and _G.copy_px.height < _G.source.height]],
      note = "the copy is smaller than the source: a crop, not the whole picture",
    },
    {
      expect = [[_G.want and _G.copy_px.width == _G.want.w and _G.copy_px.height == _G.want.h]],
      note = "its size is the rectangle of zoom level 2",
    },
    {
      expect = [[_G.moved ~= nil and _G.bytes(_G.copied) == _G.bytes(_G.moved)]],
      note = "it is the crop after the move right, byte for byte",
    },
    {
      expect = [[(function()
        for _, p in ipairs(_G.centred) do
          if _G.bytes(p) == _G.bytes(_G.copied) then return false end
        end
        return true
      end)()]],
      note = "and none of the crops before the move",
    },
    { keys = "q", note = "close the hover" },
    { wait = [[_G.float() == nil]], note = "the float is gone" },
  },
  judge = {},
  manual = {
    "With the real clipboard: the path Y reported pastes into another program, and the file it names shows the detail that was on screen",
    "A PDF page and a page screenshot (:Hover links web shot), zoomed and moved, then Y: the copy is the view on screen",
  },
}
