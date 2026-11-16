-- Feature hover.directory (TESTS/sheets/features.lua), the part only filetree.nvim's own tree can do: a reader of
-- notes.md rests the cursor on the path docs/ in a sentence and asks for the hover; the float lists the folder. With a
-- key named for `dir_keys.expand` (there is none by default) the selected folder is shown open where it stands, its
-- entries indented under it, and closed again by the same key; moving the cursor takes the float away and with it the
-- borrowed key, and nothing of the tree is left behind (docs/FEATURES/DIRECTORY.md). The same holds for the mouse:
-- the wheel over the note beside the float and a click there (replayed as an ordinary click) take the float and free
-- the key, as events through nvim_input_mouse on the attached UI.
-- Acceptance: hover.nvim/abnahme-directory-hover-folder-open-in-place. filetree.nvim comes from .deps/ (CI:
-- ci.workflow.checkouts in .testing.lua) or beside this repository; without it the sheet is a reported skip (n/a).
return {
  id = "hover.directory-expand",
  feature = "hover.directory",
  title = "hover.nvim: a folder of the directory hover is shown open in place with dir_keys.expand, and the float cleans up",
  task = "hover.nvim/abnahme-directory-hover-folder-open-in-place",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
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
      -- no Nerd Font in a snapshot: the tree draws no icons
      vim.g.have_nerd_font = false
      require("filetree").setup({ adapter = "native", deps_popup = false })
      require("hover").setup({ dir_keys = { expand = { "o" } } })]],
      note = "filetree.nvim on its own tree; hover with a key named for dir_keys.expand",
    },
    {
      lua = [[_G.sandbox()
      for _, rel in ipairs({ "docs/api/client.md", "docs/api/server.md", "docs/img/logo.txt", "docs/guide.md" }) do
        vim.fn.mkdir(vim.fs.dirname(_G.root .. "/" .. rel), "p")
        vim.fn.writefile({ rel }, _G.root .. "/" .. rel)
      end
      _G.open("notes.md", "see docs/ for the details")
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      _G.before = { bufs = #vim.api.nvim_list_bufs(), o = vim.fn.maparg("o", "n") }]],
      note = "a project with a folder docs/, notes.md open, the cursor on the path of the folder",
    },
    { keys = ":Hover show<CR>", note = "hover the path" },
    {
      wait = [[_G.float() ~= nil and _G.float_text():find("guide.md", 1, true) ~= nil]],
      note = "the float lists docs/",
    },
    { expect = [[_G.has(_G.float_text(), "api")]], note = "its folders" },
    {
      expect = [[_G.float_text():find("client.md", 1, true) == nil]],
      note = "flat: nothing of what is inside a folder",
    },
    { screen = "listing" },
    { keys = "o", note = "dir_keys.expand on the selected folder (the first entry, api)" },
    {
      wait = [[_G.float_text():find("client.md", 1, true) ~= nil and _G.float_text():find("server.md", 1, true) ~= nil]],
      note = "the folder is shown open in place: its entries are listed",
    },
    {
      expect = [[_G.eq(_G.text(), "see docs/ for the details")]],
      note = "the key was the hover's: `o` opened no line in the note",
    },
    { screen = "folder-open" },
    { keys = "o", note = "the same key again" },
    {
      wait = [[_G.float() ~= nil and _G.float_text():find("client.md", 1, true) == nil]],
      note = "the folder is closed again, the float still there",
    },
    { keys = "o", note = "open it once more, and leave with it open" },
    { wait = [[_G.float_text():find("client.md", 1, true) ~= nil]] },
    { keys = "$", note = "move the cursor away" },
    { wait = [[_G.float() == nil]], note = "the float is gone" },
    {
      expect = [[_G.eq(vim.fn.maparg("o", "n"), _G.before.o)]],
      note = "the borrowed key is given back",
    },
    {
      expect = [[_G.eq(#vim.api.nvim_list_bufs(), _G.before.bufs)]],
      note = "no buffer of the tree or the float is left behind",
    },
    {
      expect = [[_G.eq(#vim.api.nvim_list_wins(), 1)]],
      note = "and no window",
    },
    {
      lua = [[vim.o.mouse = "a"
      local more = {}
      for i = 2, 80 do more[#more + 1] = ("more of the note, line %02d"):format(i) end
      vim.api.nvim_buf_set_lines(0, 1, -1, false, more)
      vim.bo.modified = false
      vim.api.nvim_win_set_cursor(0, { 1, 5 })]],
      note = "the mouse on, the note long enough to scroll, the cursor on the path again",
    },
    { keys = ":Hover show<CR>", note = "hover the path again" },
    { wait = [[_G.float() ~= nil and _G.float_text():find("guide.md", 1, true) ~= nil]] },
    { keys = "o", note = "a folder open" },
    { wait = [[_G.float_text():find("client.md", 1, true) ~= nil]] },
    {
      lua = [[vim.api.nvim_input_mouse("wheel", "down", "", 0, 20, 70)]],
      note = "the wheel over the note, beside the float",
    },
    { wait = [[_G.float() == nil]], note = "the float is gone" },
    {
      expect = [[_G.eq(vim.fn.maparg("o", "n"), _G.before.o)]],
      note = "the key is free again",
    },
    {
      lua = [[vim.cmd("normal! gg"); vim.api.nvim_win_set_cursor(0, { 1, 5 })]],
      note = "back on the path",
    },
    { keys = ":Hover show<CR>", note = "and the hover once more" },
    { wait = [[_G.float() ~= nil and _G.float_text():find("guide.md", 1, true) ~= nil]] },
    { keys = "o", note = "a folder open" },
    { wait = [[_G.float_text():find("client.md", 1, true) ~= nil]] },
    {
      lua = [[vim.api.nvim_input_mouse("left", "press", "", 0, 15, 70)
      vim.api.nvim_input_mouse("left", "release", "", 0, 15, 70)]],
      note = "a click on the note, beside the float",
    },
    { wait = [[_G.float() == nil]], note = "the float is gone" },
    {
      expect = [[_G.eq(vim.api.nvim_win_get_cursor(0)[1], 16)]],
      note = "the click was an ordinary click: the cursor is on the line clicked",
    },
    {
      expect = [[_G.eq(vim.fn.maparg("o", "n"), _G.before.o)]],
      note = "the key is free again",
    },
  },
  judge = {
    "The open folder reads as a tree: api with client.md and server.md indented under it, then img, then guide.md",
    "The selection is visible on the folder that was opened",
  },
  manual = {
    "In the real config with a Nerd Font and dir_keys.expand set: the icons of the open folder line up, the float grows downwards and does not jump",
    "With a real mouse in the real config: open a folder, then the wheel or a click beside the float takes it as the sheet says",
  },
}
