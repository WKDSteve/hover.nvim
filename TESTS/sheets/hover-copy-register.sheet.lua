-- Live check: `:Hover copy` / `Y`, the register part
-- (task hover.nvim/copy-live-check, points "Text-Hover, `Y`" and "nach `<C-Down>`").
-- Automated: a text hover over a file, `Y` puts the lines on screen (without the title) linewise
-- into the unnamed register; after `<C-Down>` `Y` takes the scrolled lines; `:Hover copy` does the
-- same as `Y`. lib.nvim's clipboard call is stubbed in the child and records what it was handed:
-- the real system clipboard, pasting into another program and the picture crop stay by hand.
return {
  id = "hover.copy-register",
  title = "hover.nvim: :Hover copy / Y into the register",
  task = "hover.nvim/copy-live-check",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = {
    {
      lua = 'vim.opt.shortmess:append("I"); vim.o.laststatus = 0; vim.o.ruler = false',
      note = "no intro, no status line (it would name the temporary path)",
    },
    {
      lua = [[package.loaded["lib.nvim.cross.copy_to_clipboard"] = function(text)
        _G.clipped = _G.clipped or {}
        _G.clipped[#_G.clipped + 1] = text
        return true
      end
      require("hover").setup({})]],
      note = "hover.nvim with its defaults; the system clipboard stubbed",
    },
    {
      lua = [[local root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      local lines = {}
      for i = 1, 60 do lines[i] = ("line %02d of the target"):format(i) end
      vim.fn.writefile(lines, root .. "/target.txt")
      vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"
      vim.cmd.edit(vim.fn.fnameescape(root .. "/notes.md"))
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "see ./target.txt here" })
      vim.bo.modified = false
      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      vim.fn.setreg('"', "")]],
      note = "a buffer naming a 60-line file, the cursor on the name",
    },
    { keys = ":Hover show<CR>", note = "open the hover" },
    {
      wait = [[#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins()) > 0]],
      note = "the float is up",
    },
    { settle = 500 },
    { screen = "text-hover" },
    { keys = "Y", note = "copy what the hover shows" },
    {
      expect = [[vim.fn.getreg('"'):find("^line 01 of the target\nline 02 of the target\n") ~= nil]],
      note = "the register starts with the first lines of the file",
    },
    { expect = [[vim.fn.getregtype('"') == "V"]], note = "linewise" },
    {
      expect = [[vim.fn.getreg('"'):find("target.txt", 1, true) == nil]],
      note = "without the title",
    },
    {
      expect = [[_G.clipped and #_G.clipped == 1 and _G.clipped[1] == vim.fn.getreg('"')]],
      note = "the same text was handed to the clipboard",
    },
    { keys = "<C-Down>", note = "scroll the hover" },
    { settle = 300 },
    { keys = "Y", note = "copy again" },
    {
      expect = [[vim.fn.getreg('"'):find("^line 21 of the target\n") ~= nil
        and vim.fn.getreg('"'):find("line 01 of", 1, true) == nil]],
      note = "the register holds the scrolled lines (a page further: 21 on), not the first ones",
    },
    { lua = [[_G.after_scroll = vim.fn.getreg('"')]] },
    { lua = [[vim.fn.setreg('"', "")]] },
    { keys = ":Hover copy<CR>", note = ":Hover copy instead of Y" },
    {
      expect = [[vim.fn.getreg('"') == _G.after_scroll and vim.fn.getregtype('"') == "V"]],
      note = ":Hover copy fills the register as Y does",
    },
    { keys = "q", note = "close the hover" },
    {
      wait = [[#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins()) == 0]],
      note = "the float is gone",
    },
    {
      expect = [[vim.fn.maparg("Y", "n", false, true).desc ~= "hover: copy what this hover shows"]],
      note = "Y is handed back",
    },
  },
  judge = {
    "The text hover in the snapshot shows the lines Y copies, and no title row among them",
  },
  manual = {
    "Text hover, Y, paste into another program: the lines on screen arrive through the real system clipboard, without the title",
    "Image hover, > twice, move with l, Y: the reported file under stdpath('cache')/hover.nvim/copies shows the crop, not the whole picture; likewise a PDF page and a page screenshot",
    "Enter the result (a failure too) in the row 'A hover copied' of NOTES/MANUAL-EVIDENCE.md",
  },
}
