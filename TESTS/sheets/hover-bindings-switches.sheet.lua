-- The :Hover commands of the nvim config's BINDINGS-RUNTIME-CHECKLIST.md that set what hovers (task
-- hover.nvim/testblatt-bindings-checkliste): the twelve switches (`:Hover links`, `links web`, `links web fetch`,
-- `links web fetch pdf`, `links web shot`, `links web shot eager`, `paths`, `paths missing`, `paths code`, `images`,
-- `positions`, `office`), `:Hover all`, `mode`, `auto`, `border`, `toggle`, `dashboard` and `why`. Each one is typed as
-- the checklist names it and the sheet reads what it did: the switch's state, the message it gave, and where it is
-- cheap the effect itself (a type switched to open by itself opens on CursorHold; `paths` off and `:Hover why` says
-- so; a border style is the border of the next float). hover.nvim is set up as the nvim config does
-- (TESTS/sheets/_bindings.lua). What a switch does to a fetch, a browser or LibreOffice is not looked at here: the
-- http sheets and the `manual` lines say where that is.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
    dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
    note = "hover.nvim as the nvim config sets it up, messages recorded",
  },
  {
    lua = [[_G.sandbox()
    local guide = {}
    for i = 1, 60 do guide[i] = ("guide line %02d"):format(i) end
    vim.fn.mkdir(_G.root .. "/docs", "p")
    vim.fn.writefile(guide, _G.root .. "/docs/guide.txt")
    _G.open("notes.md", "# Notes", "", "see docs/guide.txt for the guide", "", "nothing here at all")
    -- the config leaves 'updatetime' at 4 s; CursorHold follows it, the sheet need not wait that long
    vim.o.updatetime = 200]],
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

---Type the bare switch command twice: it flips the switch, says so, and flips it back.
---@param words string  the route as the checklist names it
---@param name string   the switch (hover.switches)
local function flip(words, name)
  add({ lua = ("_G.was = _G.sw(%q)"):format(name) })
  type_cmd(words, "flips the switch " .. name)
  add({
    expect = ("_G.sw(%q) == not _G.was"):format(name),
    note = "the switch " .. name .. " flipped",
  })
  add({ wait = [[#_G.notes > 0]], note = "and it said what it did" })
  type_cmd(words, "again")
  add({ expect = ("_G.sw(%q) == _G.was"):format(name), note = "back as it was" })
end

-- ---------- mode, auto, why: what opens by itself ----------
type_cmd("mode", "reports the mode")
add({ wait = [[_G.noted("mode: auto")]], note = "auto, as the config leaves it" })
type_cmd("auto", "reports which types open by themselves")
add({ wait = [[_G.noted("opens by itself: ") and _G.noted("only on request: ")]] })
add({
  expect = [[require("hover.config").auto_hover_for("image") and not require("hover.config").auto_hover_for("file")]],
  note = "pictures open by themselves, a file only on request (the config keeps hover's default)",
})
add({ keys = "3G0fd", note = "the cursor on docs/guide.txt" })
type_cmd("why", "says why nothing hovered")
add({
  wait = [[_G.noted("file targets do not open by themselves")]],
  note = "the path was found, but file targets do not open by themselves",
})
type_cmd("auto file", "lets a file open by itself")
add({ wait = [[_G.noted("file opens by itself")]] })
add({ keys = "l", note = "a key, then nothing: CursorHold" })
add({
  wait = [[_G.float() ~= nil and _G.has(_G.float_text(), "guide line 01")]],
  timeout = 3000,
  note = "the trigger opened the file by itself",
})
add({ keys = "5G", note = "away to a line without a target" })
add({ wait = [[_G.float() == nil]] })
type_cmd("auto file", "back to on request only")
add({ wait = [[_G.noted("file does not open by itself")]] })

-- ---------- the switches ----------
flip("links", "links")
flip("links web", "web")
flip("links web fetch", "fetch")
flip("links web fetch pdf", "pdf")
flip("links web shot", "shot")
flip("links web shot eager", "eager")
flip("paths", "paths")
flip("paths missing", "missing")
flip("paths code", "code")
flip("images", "images")
flip("positions", "positions")
flip("office", "office")

-- `implies`: a switch turned on turns on what it needs.
type_cmd("links web off", "web links off")
add({ expect = [[not _G.sw("web") and not _G.sw("fetch")]] })
type_cmd("links web fetch on", "fetch on, with web off")
add({
  expect = [[_G.sw("fetch") and _G.sw("web") and _G.sw("links")]],
  note = "fetch took links web with it",
})
type_cmd("links web fetch off", "fetch off again")
type_cmd("links web off", "and web")

-- `paths` off is what :Hover why names.
type_cmd("paths off", "bare paths off")
add({ keys = "3G0fd", note = "the cursor on docs/guide.txt again" })
type_cmd("why", "why nothing hovers now")
add({
  wait = [[_G.noted("bare paths: off")]],
  note = "bare paths are off, and the command to undo it",
})
type_cmd("paths on", "bare paths on again")
add({ expect = [[_G.sw("paths")]] })

-- ---------- border ----------
type_cmd("border double", "a double border")
add({ wait = [[_G.noted("border: double")]] })
add({ keys = ":Hover show<CR>", note = "a hover to look at" })
add({ wait = [[_G.float() ~= nil]] })
add({
  expect = [[_G.float_config().border[1] == "╔"]],
  note = "the float is drawn with the double border",
})
add({ settle = 2000 })
add({ screen = "double-border" })
add({ keys = "q" })
add({ wait = [[_G.float() == nil]] })
type_cmd("border", "reports the style")
add({ wait = [[_G.noted("border: double  ·  available: ")]] })
type_cmd("border rounded", "back to the config's")

-- ---------- toggle, mode ----------
type_cmd("toggle", "the hover off for this session")
add({ wait = [[_G.noted("hover off")]] })
add({ expect = [[not require("hover").is_enabled() and require("hover").mode() == "off"]] })
type_cmd("toggle", "and on again")
add({ wait = [[_G.noted("hover on")]] })
add({ expect = [[require("hover").is_enabled() and require("hover").mode() == "auto"]] })
type_cmd("mode manual", "only on request")
add({ wait = [[_G.noted("hover manual")]] })
add({ expect = [[require("hover").mode() == "manual"]] })
type_cmd("mode auto", "back to auto")
add({ expect = [[require("hover").mode() == "auto"]] })

-- ---------- all ----------
type_cmd("all on", "everything on")
add({ wait = [[_G.noted("hover on: every switch, every type, mode auto")]] })
add({
  expect = [[(function()
    for _, s in ipairs(require("hover").status().switches) do
      if not s.enabled then return false end
    end
    return require("hover.config").auto_hover_for("file") and require("hover").mode() == "auto"
  end)()]],
  note = "every switch on, every type opens by itself, mode auto",
})
type_cmd("all off", "everything off")
add({ wait = [[_G.noted("hover off: every switch off")]] })
add({ expect = [[require("hover").mode() == "off" and not _G.sw("paths")]] })
type_cmd("all", "flipped as a whole: on, since not everything is on")
add({ wait = [[_G.noted("hover on: every switch")]] })
add({ expect = [[require("hover").mode() == "auto" and _G.sw("paths")]] })

-- ---------- dashboard ----------
type_cmd("dashboard", "the board")
add({ wait = [[_G.float() ~= nil and _G.has(_G.float_text(), ":Hover links web")]], timeout = 3000 })
add({
  expect = [[_G.has(_G.float_text(), "mode")]],
  note = "the mode and every switch with its command",
})
-- steady, not settle: the board keeps a timer of its own for as long as it is open
add({ steady = 300 })
add({ screen = "dashboard" })
add({ keys = "q", note = "close the board" })
add({ wait = [[_G.float() == nil]] })

return {
  id = "hover.bindings-switches",
  title = "hover.nvim: the switch, mode, auto, border, toggle, dashboard and why commands of the bindings checklist",
  task = "hover.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = steps,
  judge = {
    "The double border in the snapshot is drawn whole (corners and sides)",
    "The board lists the mode and every switch with the command that acts on it",
  },
  manual = {
    "links web fetch / fetch pdf / shot / shot eager and office do what their line says on a real link and a real office file (network, a headless browser, LibreOffice): the switch state is automated here, the effect in the http sheets and by hand",
    "images: a picture hover draws the picture with the switch on and a description with it off, in a terminal that draws pictures",
    "positions: a plugin of the config (documentation.nvim, insights.nvim) answers over a dotted name with the switch on and is silent with it off",
    "paths code: a path inside Lua code hovers only with the switch on (a comment or string always)",
  },
}
