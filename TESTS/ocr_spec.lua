---@diagnostic disable: need-check-nil
-- The test body is the guard; see the note in TESTS/bare_path_spec.lua
-- (`LLS-42`).

-- TESTS/ocr_spec.lua -- `:Hover ocr` / `gO`: the text of the picture on
-- screen, through images.nvim's OCR.
--
-- images.nvim and tesseract are not needed: the answers that do not reach
-- them are pinned on a real float, and `images` is stood in for where one
-- would be asked.

describe("hover.ocr on a real float", function()
  local config = require("hover.config")
  local keys = require("hover.bindings.keymaps")
  local registry = require("hover.registry")
  local hover = require("hover")
  local root, win, prev_buf, buf, prev_isfname

  before_each(function()
    config.reset()
    registry.reset()
    keys.release()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "first line", "second line" }, root .. "/two.txt")
    prev_isfname = vim.o.isfname
    vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"
    win = vim.api.nvim_get_current_win()
    prev_buf = vim.api.nvim_win_get_buf(win)
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
  end)

  it("says so when no hover is open", function()
    local ok, message = hover.ocr()
    assert.is_false(ok)
    assert.same("no hover to read", message)
  end)

  it("says so when the hover shows no picture", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see ./two.txt here" })
    vim.api.nvim_win_set_cursor(win, { 1, 5 })
    assert.is_true(hover.show({ force = true }), "no hover opened")
    local ok, message = hover.ocr()
    assert.is_false(ok)
    assert.same("this hover shows no picture to read", message)
  end)

  it("binds gO while a float is up, and hands it back after", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see ./two.txt here" })
    vim.api.nvim_win_set_cursor(win, { 1, 5 })
    assert.is_true(hover.show({ force = true }))
    local m = vim.fn.maparg("gO", "n", false, true)
    assert.same("hover: read the text of the picture this hover shows", m.desc)
    hover.hide()
    local after = vim.fn.maparg("gO", "n", false, true)
    assert.are_not.equal("hover: read the text of the picture this hover shows", after.desc)
  end)
end)
