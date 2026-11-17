-- What six :Hover switches of the nvim config's BINDINGS-RUNTIME-CHECKLIST.md do, not only that they flip
-- (hover.bindings-switches does that): `:Hover links`, `links web`, `links web fetch`, `paths missing`, `paths code` and
-- `positions`, each on a target of its own. `:Hover show` passes every switch by design, so the effect is read where the
-- switches act: the automatic trigger (CursorHold, with `:Hover auto all`) opens a float with the switch on, and with it
-- off `:Hover why` names that switch as the reason. hover.nvim is set up as the nvim config does
-- (TESTS/sheets/_bindings.lua); the network is the stub of TESTS/sheets/_helpers.lua (`net_stub`), so `fetch` is one
-- recorded request, not a connection. What stays by hand (a real page, `shot`, `office`, `images`) is in the manual
-- lines and in hover.nvim/abnahme-bindings-testblaetter.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
    _G.net_stub({ ["https://example.test/page"] = _G.fixture("example-page") })
    dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
    note = "hover.nvim as the nvim config sets it up, the network a stub",
  },
  {
    lua = [[_G.sandbox()
    vim.fn.mkdir(_G.root .. "/docs", "p")
    vim.fn.writefile({ "guide line 01", "guide line 02" }, _G.root .. "/docs/guide.txt")
    vim.fn.writefile({ "return docs/guide.txt" }, _G.root .. "/code.lua")
    _G.open("notes.md", "see [the guide](docs/guide.txt) here", "web https://example.test/page link",
      "gone ./docs/gone.txt path", "plain words only")
    -- the config leaves 'updatetime' at 4 s; CursorHold follows it, the sheet need not wait that long
    vim.o.updatetime = 200]],
    note = "notes.md: a markdown link, an https link, a path to nothing, plain words; code.lua names a path in code",
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

---Rest the cursor (keys), and wait for the float the trigger opens.
---@param keys string
---@param want string  text the float shows
---@param note string
local function opens(keys, want, note)
  add({ keys = keys, note = "the cursor there, then nothing typed: CursorHold" })
  add({
    wait = ("_G.float() ~= nil and _G.float_text():find(%q, 1, true) ~= nil"):format(want),
    timeout = 3000,
    note = note,
  })
  add({
    keys = ":enew<CR>:b #<CR>",
    note = "away and back (no <Esc>: that would dismiss the target)",
  })
  add({ wait = [[_G.float() == nil]] })
end

---Rest the cursor (keys) with the switch off: `:Hover why` names it.
---@param keys string
---@param reason string
---@param note string
local function refused(keys, reason, note)
  add({ keys = keys, note = "the cursor there" })
  type_cmd("why", "why nothing hovers")
  add({ wait = ("_G.noted(%q)"):format(reason), note = note })
  add({ expect = [[_G.float() == nil]], note = "and no float came" })
end

type_cmd("auto all", "every type opens by itself, so the switches are what decides")
add({ wait = [[_G.noted("every type opens by itself")]] })

-- ---------- links ----------
opens("1G05l", "guide line 01", "links on: the markdown link opens the file it points at")
type_cmd("links off", "link targets off")
-- Off, the link is no target at all: :Hover why finds only the word under the cursor, and no `target:` line.
refused(
  "1G05l",
  'bare path: "the" is not shaped like a path',
  "links off: the link text is just a word now"
)
add({ expect = [[not _G.noted("target: ")]], note = "no target was found at the link" })
type_cmd("links on", "on again")

-- ---------- links web, links web fetch ----------
-- Off (the default), the https link is no URL target: :Hover why finds only text that is no path.
refused(
  "2G0fh",
  'bare path: "https://example.test/page" resolved to nothing',
  "web links off: the link does not hover"
)
add({ expect = [[not _G.noted("target: ")]], note = "no URL target was found" })
type_cmd("links web on", "web links on, fetch still off")
opens("2G0fhl", "example.test", "web on: the link hovers with its parsed URL")
add({ expect = [[_G.eq(#_G.requests, 0)]], note = "and nothing was fetched" })
type_cmd("links web fetch on", "fetch on")
opens("2G0fh", "HTTP 200 OK", "fetch on: the hover shows the status of the page")
add({ expect = [[_G.eq(#_G.requests, 1)]], note = "one request went out (to the stub)" })
type_cmd("links web off", "web links off again")

-- ---------- paths missing ----------
opens("3G0f.", "✗", "the marker on: a path to nothing is reported as broken")
type_cmd("paths missing off", "the marker off")
refused("3G0f.", "the broken-target marker is off", "marker off: no float, :Hover why says so")
type_cmd("paths missing on", "on again")

-- ---------- positions ----------
add({
  lua = [[require("hover.registry").register("stand-in", {
    positions = { function() return { lines = { "a stand-in answer" } } end },
  })]],
  note = "a plugin with something to say about any place (a stand-in for documentation.nvim, insights.nvim)",
})
opens("4G0w", "a stand-in answer", "positions on: its answer hovers over plain words")
type_cmd("positions off", "the class off")
refused("4G0", "registered, but the class is off", "positions off: silent, :Hover why says so")
type_cmd("positions on", "on again")

-- ---------- paths code ----------
add({
  keys = ":edit code.lua<CR>",
  note = "a Lua file: `return docs/guide.txt` is a path in executable code",
})
add({ wait = [[vim.bo.filetype == "lua"]] })
refused(
  "1G0fd",
  "sits in executable code",
  "paths code off (the default): the path in code does not hover"
)
type_cmd("paths code on", "paths in code on")
opens("1G0fdl", "guide line 01", "paths code on: the path in code opens the file")

return {
  id = "hover.bindings-effects",
  title = "hover.nvim: what links, links web, fetch, paths missing, positions and paths code do, by the trigger and :Hover why",
  task = "hover.nvim/abnahme-bindings-testblaetter",
  engine = "rpc",
  sizes = { { rows = 24, cols = 80 } },
  steps = steps,
  manual = {
    "links web fetch on a real page in the real config: the title and description arrive (hover.http-preview-live with --live)",
  },
}
