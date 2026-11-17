-- The :Hover commands of the nvim config's BINDINGS-RUNTIME-CHECKLIST.md that act on a hover on screen (task
-- hover.nvim/testblatt-bindings-checkliste): `:Hover show`, `resize`, `zen`, `pin`, `open` and `next`. Each is typed as
-- the checklist names it and the sheet reads the float: its size, whether it stays when the cursor goes, what was
-- handed to the outside, which answer it shows. hover.nvim is set up as the nvim config does
-- (TESTS/sheets/_bindings.lua). `vim.ui.open` is a recorder: nothing outside the editor starts (the config routes
-- through open.nvim, a `manual` line). Two position answers stand in for the config's documentation.nvim and
-- insights.nvim, so `:Hover next` has somewhere to step. `:Hover zoom` and `:Hover nav` need a drawn picture: they are
-- in hover-bindings-zoom.sheet.lua.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
    dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")
    vim.ui.open = function(what)
      _G.opened = what
      return { wait = function() return { code = 0 } end }
    end]],
    note = "hover.nvim as the nvim config sets it up; vim.ui.open records what it is handed",
  },
  {
    lua = [[_G.sandbox()
    local guide = {}
    for i = 1, 60 do guide[i] = ("guide line %02d"):format(i) end
    vim.fn.mkdir(_G.root .. "/docs", "p")
    vim.fn.writefile(guide, _G.root .. "/docs/guide.txt")
    _G.open("notes.md", "# Notes", "", "see docs/guide.txt for the guide", "", "nothing here at all")]],
    note = "a project: notes.md names docs/guide.txt (60 lines) in prose",
  },
}

local function add(step)
  steps[#steps + 1] = step
end

---Type `:Hover <words>` after dropping the recorded messages.
---@param words string
---@param note string
local function type_cmd(words, note)
  add({ lua = [[_G.forget()]] })
  add({ keys = ":Hover " .. words .. "<CR>", note = ":Hover " .. words .. ": " .. note })
end

-- ---------- show ----------
add({ keys = "3G0fd", note = "the cursor on docs/guide.txt" })
type_cmd("show", "the hover, although a text file does not open by itself in this config")
add({ wait = [[_G.float() ~= nil and _G.has(_G.float_text(), "guide line 01")]] })
add({ settle = 2000 })
add({ screen = "show" })

-- ---------- resize ----------
add({ lua = [[_G.h0 = _G.float_config().height]] })
type_cmd("resize smaller", "smaller")
add({ wait = [[_G.float_config().height < _G.h0]], note = "the float has fewer rows" })
type_cmd("resize", "and bigger again (the default direction)")
add({ wait = [[_G.float_config().height == _G.h0]], note = "back to the rows it had" })

-- ---------- zen ----------
add({ lua = [[_G.h0 = _G.float_config().height]] })
type_cmd("zen", "full screen")
add({
  wait = [[_G.float() ~= nil and _G.float_config().height >= vim.o.lines - 8]],
  note = "the hover is built again against the editor's height: far more of the file",
})
add({ settle = 2000 })
add({ screen = "zen" })
type_cmd("zen", "taken back")
add({
  wait = [[_G.float() ~= nil and _G.float_config().height == _G.h0]],
  note = "the float as it was",
})

-- ---------- pin ----------
type_cmd("pin", "keep it while the cursor goes")
add({ wait = [[_G.noted("hover pinned")]] })
add({ keys = "5G", note = "the cursor goes to a line without a target" })
add({ settle = 2000 })
add({ expect = [[_G.float() ~= nil]], note = "the pinned hover is still there" })
type_cmd("pin", "let it go")
add({ wait = [[_G.noted("hover released")]] })
add({ keys = "k", note = "the cursor moves" })
add({ wait = [[_G.float() == nil]], note = "a released hover goes with the next move" })

-- ---------- open ----------
add({ keys = "3G0fd", note = "back on docs/guide.txt" })
type_cmd("show", "the hover again")
add({ wait = [[_G.float() ~= nil]] })
type_cmd("open", "what it shows, outside the editor")
add({
  wait = [[type(_G.opened) == "string" and vim.fs.normalize(_G.opened):find("docs/guide.txt", 1, true) ~= nil]],
  note = "the file was handed to the system's opener",
})
add({ wait = [[_G.float() == nil]], note = "and the hover closed" })

-- ---------- next ----------
add({
  lua = [[local registry = require("hover.registry")
  for name, text in pairs({ first = "answer A", second = "answer B" }) do
    registry.register(name, { positions = { function() return { lines = { text } } end } })
  end]],
  note = "two plugins with something to say about any place (stand-ins for documentation.nvim, insights.nvim)",
})
add({ keys = "5G0", note = "a line where nothing else hovers" })
type_cmd("show", "the first answer")
add({ wait = [[_G.float() ~= nil and _G.float_text():find("answer", 1, true) ~= nil]] })
add({ lua = [[_G.first = _G.float_text()]] })
type_cmd("next", "the next plugin's answer")
add({
  wait = [[_G.float() ~= nil and _G.float_text():find("answer", 1, true) ~= nil and _G.float_text() ~= _G.first]],
  note = "the other answer",
})
type_cmd("next", "and on")
add({
  wait = [[_G.float() ~= nil and _G.float_text() == _G.first]],
  note = "past the last it wraps",
})
add({ keys = "q" })
add({ wait = [[_G.float() == nil]] })

return {
  id = "hover.bindings-float",
  title = "hover.nvim: the show, resize, zen, pin, open and next commands of the bindings checklist",
  task = "hover.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  -- 40 rows: zen builds against `lines - 4`, which at 24 rows is the 20 lines of `max_lines` again
  sizes = { { rows = 40, cols = 100 } },
  steps = steps,
  judge = {
    "The zen snapshot fills the screen with the file and reads as the same hover, not a new window",
  },
  manual = {
    ":Hover open in the real config: open.nvim (or media.nvim for a video) takes the file and the system's program opens it",
    ":Hover next over a dotted name in the real config: documentation.nvim and insights.nvim answer, and <M-n> where the terminal sends Alt",
  },
}
