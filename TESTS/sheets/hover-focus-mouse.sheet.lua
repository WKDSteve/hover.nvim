-- Feature hover.focus (TESTS/sheets/features.lua): `:Hover focus` enters a text hover so that the mouse works in it.
-- The hand check of NOTES/MANUAL-EVIDENCE.md ("`:Hover focus`: the mouse inside the float"), lines 1 to 3, as mouse
-- events through nvim_input_mouse on the attached UI: a drag with the left button selects words of the float and `y`
-- yanks them; the wheel over the float scrolls the float's text, not the window behind it; `q` and `<Esc>` lead back
-- to the window the reader came from, the float stays up, and the next cursor move closes it.
-- Line 4 (a picture hover refuses to be entered) needs a drawn picture and stays by hand, as does a real mouse.
-- Acceptance: hover.nvim/hover-focus-maus-handpruefung-auswahl-rad-q-esc.
return {
  id = "hover.focus-mouse",
  feature = "hover.focus",
  title = "hover.nvim: :Hover focus, then select with the mouse, scroll with the wheel, leave with q / <Esc>",
  task = "hover.nvim/hover-focus-maus-handpruefung-auswahl-rad-q-esc",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.o.laststatus = 0; vim.o.ruler = false
      vim.o.mouse = "a"
      require("hover").setup({})]],
      note = "hover.nvim with its defaults, the mouse on",
    },
    {
      lua = [[_G.sandbox()
      local lines = {}
      for i = 1, 60 do lines[i] = ("line %02d of the target"):format(i) end
      vim.fn.writefile(lines, _G.root .. "/target.txt")
      local note = { "see ./target.txt here" }
      for i = 2, 100 do note[i] = ("note line %03d"):format(i) end
      _G.open("notes.md", unpack(note))
      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      _G.origin = vim.api.nvim_get_current_win()
      -- The screen cell (0-based, as nvim_input_mouse takes it) of a line and column of the float's text.
      _G.cell = function(lnum, col)
        local p = vim.fn.screenpos(_G.float(), lnum, col)
        assert(p.row > 0, "line " .. lnum .. " of the float is not on the screen")
        return p.row - 1, p.col - 1
      end
      _G.topline = function(win) return vim.fn.getwininfo(win)[1].topline end]],
      note = "a 100-line note naming a 60-line file, the cursor on the name",
    },
    { keys = ":Hover show<CR>", note = "hover the path" },
    {
      wait = [[_G.float() ~= nil and _G.float_text():find("line 01 of the target", 1, true) ~= nil]],
      note = "the text hover is up",
    },
    { keys = ":Hover focus<CR>", note = "enter it" },
    {
      wait = [[vim.api.nvim_get_current_win() == _G.float()]],
      note = "the cursor is in the float",
    },
    {
      lua = [[_G.r, _G.c = _G.cell(3, 1)
      _G.c2 = select(2, _G.cell(3, 10))
      vim.api.nvim_input_mouse("left", "press", "", 0, _G.r, _G.c)]],
      note = "press the left button on the first word of the third line",
    },
    { settle = 100 },
    {
      lua = [[vim.api.nvim_input_mouse("left", "drag", "", 0, _G.r, _G.c2)]],
      note = "drag over the first words",
    },
    { settle = 100 },
    {
      lua = [[vim.api.nvim_input_mouse("left", "release", "", 0, _G.r, _G.c2)]],
      note = "and let go",
    },
    { settle = 100 },
    { wait = [[vim.api.nvim_get_mode().mode == "v"]], note = "the drag selects (Visual mode)" },
    { screen = "selection" },
    { keys = "y", note = "yank the selection" },
    {
      expect = [[_G.eq(vim.fn.getreg('"'), "line 03 of")]],
      note = "the register holds the words the drag went over",
    },
    {
      expect = [[_G.eq(vim.api.nvim_get_current_win(), _G.float())]],
      note = "still inside the float",
    },
    {
      lua = [[local r, c = _G.cell(5, 5)
      vim.api.nvim_input_mouse("wheel", "down", "", 0, r, c)]],
      note = "the wheel down over the float",
    },
    { wait = [[_G.topline(_G.float()) > 1]], note = "the float's own text scrolls" },
    {
      expect = [[_G.eq(_G.topline(_G.origin), 1)]],
      note = "the window behind it does not",
    },
    { keys = "q", note = "leave with q" },
    {
      wait = [[vim.api.nvim_get_current_win() == _G.origin]],
      note = "back in the window the reader came from",
    },
    { expect = [[_G.float() ~= nil]], note = "the float stays up" },
    { keys = "j", note = "the next cursor move" },
    { wait = [[_G.float() == nil]], note = "closes it" },
    { keys = "k", note = "back onto the path" },
    { lua = [[vim.api.nvim_win_set_cursor(0, { 1, 6 })]] },
    { keys = ":Hover show<CR>", note = "the hover again" },
    { wait = [[_G.float() ~= nil]] },
    { keys = ":Hover focus<CR>" },
    { wait = [[vim.api.nvim_get_current_win() == _G.float()]] },
    { keys = "<Esc>", note = "leave with <Esc>" },
    {
      wait = [[vim.api.nvim_get_current_win() == _G.origin]],
      note = "back in the window the reader came from",
    },
    { expect = [[_G.float() ~= nil]], note = "the float stays up" },
    { keys = "j", note = "the next cursor move" },
    { wait = [[_G.float() == nil]], note = "closes it" },
  },
  judge = {
    "The selection in the snapshot covers exactly the words the drag went over, drawn as a Visual selection inside the float",
  },
  manual = {
    "With a real mouse in the real config: drag over words of a text hover after :Hover focus, the wheel inside it, q and <Esc>; it behaves as the sheet says",
    "A picture hover: :Hover focus answers 'a picture hover cannot be entered' instead of entering",
  },
}
