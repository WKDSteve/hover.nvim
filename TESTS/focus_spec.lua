---@diagnostic disable: need-check-nil
-- The test body is the guard; see the note in TESTS/bare_path_spec.lua
-- (`LLS-42`).

-- TESTS/focus_spec.lua -- `:Hover focus`: entering a text hover so that mouse and Visual selection work in it.
--
-- What is pinned: the float becomes focusable and the reader's cursor is in it; its dismissal (which would close it
-- on the first cursor move, its own included) is gone while the reader is inside and comes back on the way out;
-- `q` / `<Esc>` are buffer-local to the float and lead back to the origin window; a pin the reader set survives
-- the visit and one this took does not; the float stays up after leaving, until the next movement.

local config = require("hover.config")
local keys = require("hover.bindings.keymaps")
local float = require("hover.float")
local registry = require("hover.registry")
local hover = require("hover")

describe("hover.focus", function()
  local root, win, prev_buf, prev_isfname, buf

  before_each(function()
    config.reset()
    registry.reset()
    keys.release()
    vim.g.hover_disable = nil
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "alpha", "beta", "gamma" }, root .. "/few.txt")

    win = vim.api.nvim_get_current_win()
    prev_buf = vim.api.nvim_win_get_buf(win)
    prev_isfname = vim.o.isfname
    vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, root .. "/notes.md")
    vim.api.nvim_win_set_buf(win, buf)
  end)

  after_each(function()
    hover.hide()
    keys.release()
    pcall(vim.api.nvim_win_set_buf, win, prev_buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    vim.o.isfname = prev_isfname
    vim.fn.delete(root, "rf")
    config.reset()
    registry.reset()
    vim.g.hover_disable = nil
  end)

  local function open_hover()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see ./few.txt here" })
    vim.api.nvim_win_set_cursor(win, { 1, 5 })
    assert.is_true(hover.show({ force = true }))
    assert.is_truthy(float.win())
  end

  local function dismiss_autocmds()
    local ok, found = pcall(vim.api.nvim_get_autocmds, { group = "HoverDismiss" })
    return ok and #found or 0
  end

  it("refuses when there is no hover", function()
    local ok, why = hover.focus()
    assert.is_false(ok)
    assert.truthy(why:find("no hover", 1, true))
  end)

  it("enters the float: focusable, cursor inside, pinned, dismissal gone", function()
    open_hover()
    assert.is_true(dismiss_autocmds() > 0)
    local ok = hover.focus()
    assert.is_true(ok)
    local fw = float.win()
    assert.same(fw, vim.api.nvim_get_current_win())
    assert.is_true(vim.api.nvim_win_get_config(fw).focusable)
    assert.is_true(hover.pinned())
    assert.is_true(float.is_focused())
    assert.same(0, dismiss_autocmds(), "nothing may close the float on its own cursor move")
  end)

  it(
    "q leaves: back to the origin window, float stays, dismissal and focusability restored, pin released",
    function()
      open_hover()
      hover.focus()
      local fw = float.win()
      local found = false
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(fw), "n")) do
        if m.lhs == "q" then
          found = true
        end
      end
      assert.is_true(found, "q is buffer-local in the float")

      vim.api.nvim_feedkeys("q", "x", false)
      assert.same(win, vim.api.nvim_get_current_win())
      assert.same(fw, float.win(), "the float stays")
      assert.is_false(vim.api.nvim_win_get_config(fw).focusable)
      assert.is_false(hover.pinned(), "the pin the visit took is gone")
      assert.is_true(dismiss_autocmds() > 0, "the next movement closes it again")
      assert.is_false(float.is_focused())
    end
  )

  it("<Esc> leaves too", function()
    open_hover()
    hover.focus()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    assert.same(win, vim.api.nvim_get_current_win())
    assert.is_truthy(float.win())
  end)

  it("keeps a pin the reader set themselves", function()
    open_hover()
    hover.pin(true)
    hover.focus()
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_true(hover.pinned(), "a pin set before the visit stays")
  end)

  it("lets ordinary keys work inside: yank puts the float's own text in the register", function()
    open_hover()
    hover.focus()
    vim.fn.setreg('"', "")
    vim.api.nvim_feedkeys("yy", "x", false)
    assert.is_true(#vim.fn.getreg('"') > 0, "yy yanked a line of the hover")
    vim.api.nvim_feedkeys("q", "x", false)
  end)

  it("the borrowed keys step aside inside the float", function()
    open_hover()
    local called = 0
    -- a stand-in for any borrowed key: taken through the same wrapper the real ones use
    keys.release()
    keys.borrow(nil, {
      scroll = function()
        called = called + 1
      end,
    })
    hover.focus()
    assert.is_true(float.is_focused())
    vim.api.nvim_feedkeys("j", "x", false)
    assert.same(0, called, "a borrowed key does not act on the hover while the reader is in it")
    vim.api.nvim_feedkeys("q", "x", false)
  end)
end)
