-- TESTS/float_placement_spec.lua -- where `hover.float` puts a float next to
-- the cursor on a small screen.
--
-- On 80x24 with the cursor on row 3, a 20-line text hover (22 rows with its
-- ring) fit neither below nor above the line. It was put below regardless,
-- Neovim pushed it up to fit the screen, and its frame covered the cursor
-- line -- the target it described (seen in the bindings sheets' 80x24
-- snapshots). The float now goes below, else above, else onto the larger side
-- cut to the rows there; `size_for` reports that cut so `hover.resize` sees
-- it as a refusal.

local float = require("hover.float")

local api = vim.api

---@param n integer
---@return string[]
local function numbered(n)
  local lines = {}
  for i = 1, n do
    lines[i] = ("line %02d"):format(i)
  end
  return lines
end

---Rows (1-based, inclusive) the open float's frame covers.
---@return integer top
---@return integer bottom
local function frame_rows()
  local win = assert(float.win())
  local cfg = api.nvim_win_get_config(win)
  local ring = (cfg.border and cfg.border ~= "none") and 1 or 0
  local row = type(cfg.row) == "table" and cfg.row[false] or cfg.row
  local top = math.floor(row) + 1
  return top, top + cfg.height + 2 * ring - 1
end

---@return integer row 1-based screen row of the cursor
local function cursor_row()
  local cursor = api.nvim_win_get_cursor(0)
  return vim.fn.screenpos(0, cursor[1], cursor[2] + 1).row
end

describe("hover.float placement on a small screen", function()
  local saved_lines, saved_cols

  before_each(function()
    saved_lines, saved_cols = vim.o.lines, vim.o.columns
    vim.o.lines, vim.o.columns = 24, 80
    vim.cmd("enew!")
    api.nvim_buf_set_lines(0, 0, -1, false, numbered(23))
  end)

  after_each(function()
    float.close()
    vim.cmd("enew!")
    vim.o.lines, vim.o.columns = saved_lines, saved_cols
  end)

  ---@param line integer buffer line to put the cursor on
  ---@param n integer lines of hover text
  ---@param border string
  local function open_at(line, n, border)
    api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd("redraw")
    local opts = { max_height = 20, border = border }
    local want_w, want_h = float.size_for(numbered(n), opts)
    float.open(numbered(n), opts)
    local got_w, got_h = float.size()
    assert.are.same(
      { want_w, want_h },
      { got_w, got_h },
      "size_for agrees with the float on screen"
    )
  end

  it("cuts a float that fits neither below nor above, and keeps the cursor line free", function()
    vim.cmd("normal! gg")
    open_at(3, 60, "double")
    local cur = cursor_row()
    assert.are.equal(3, cur)
    local top, bottom = frame_rows()
    assert.is_true(top > cur, ("frame %d..%d covers the cursor row %d"):format(top, bottom, cur))
    assert.is_true(
      bottom <= vim.o.lines - vim.o.cmdheight,
      "the frame stays above the command line"
    )
    assert.are.equal(
      18,
      select(2, float.size()),
      "20 rows wanted, 20 rows free below: 18 text rows and the ring"
    )
  end)

  it("goes above the cursor line when it fits there and not below", function()
    -- Cursor on the screen's row 20: three rows below it, nineteen above.
    api.nvim_win_set_cursor(0, { 20, 0 })
    vim.cmd("normal! zb")
    api.nvim_win_set_cursor(0, { 20, 0 })
    vim.cmd("redraw")
    local cur = cursor_row()
    float.open(numbered(10), { max_height = 20, border = "rounded" })
    local top, bottom = frame_rows()
    assert.is_true(bottom < cur, ("frame %d..%d covers the cursor row %d"):format(top, bottom, cur))
    assert.are.equal(10, select(2, float.size()), "not cut: ten lines fit above")
  end)

  it("stays below the line when it fits there, as before", function()
    vim.cmd("normal! gg")
    open_at(3, 5, "rounded")
    local top = frame_rows()
    assert.are.equal(cursor_row() + 1, top)
    assert.are.equal(5, select(2, float.size()))
  end)

  it("counts no ring for border none", function()
    vim.cmd("normal! gg")
    open_at(3, 60, "none")
    local top, bottom = frame_rows()
    assert.is_true(top > cursor_row())
    assert.are.equal(20, select(2, float.size()), "20 rows free below, all of them text")
    assert.is_true(bottom <= vim.o.lines - vim.o.cmdheight)
  end)
end)
