---@diagnostic disable: need-check-nil
-- The test body is the guard; see the note in TESTS/bare_path_spec.lua
-- (`LLS-42`).

-- TESTS/missing_notify_spec.lua -- a target that resolves to nothing is also
-- reported in a message, but only for an explicit request (`hover.show({
-- force = true })`). The automatic trigger passes over a document full of dead
-- links and must stay quiet; so must text the bare-path rules call ambiguous.
-- The marker in the float is unchanged either way.

local config = require("hover.config")
local registry = require("hover.registry")
local hover = require("hover")
local notify = require("hover.notify")

describe("hover.show on a target that resolves to nothing", function()
  local root, win, prev_buf, buf, warnings, real_warn

  ---@param line string
  local function set_line(line)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.api.nvim_win_set_cursor(win, { 1, 2 })
  end

  before_each(function()
    config.reset()
    registry.reset()
    hover.hide()

    root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.tempname(), ":p"))
    vim.fn.mkdir(root, "p")
    win = vim.api.nvim_get_current_win()
    prev_buf = vim.api.nvim_win_get_buf(win)
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, root .. "/notes.md")
    vim.api.nvim_win_set_buf(win, buf)

    warnings = {}
    real_warn = notify.warn
    notify.warn = function(msg)
      warnings[#warnings + 1] = msg
    end
  end)

  after_each(function()
    notify.warn = real_warn
    hover.hide()
    pcall(vim.api.nvim_win_set_buf, win, prev_buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    vim.fn.delete(root, "rf")
    config.reset()
    registry.reset()
  end)

  it("says so once for an explicit request, naming the path and the base folder", function()
    local gone = root .. "/gone.md"
    set_line(gone)
    assert.is_true(hover.show({ force = true }))
    assert.equals(1, #warnings)
    assert.is_truthy(warnings[1]:find("gone.md", 1, true))
    assert.is_truthy(warnings[1]:find(vim.fs.dirname(root .. "/notes.md"), 1, true))
  end)

  it("stays quiet for the automatic trigger, the marker still opens", function()
    set_line(root .. "/gone.md")
    hover.show({})
    assert.equals(0, #warnings)
  end)

  it("stays quiet when the switch is off", function()
    set_line(root .. "/gone.md")
    require("hover.switches").set("notify", false, { silent = true })
    assert.is_true(hover.show({ force = true }))
    assert.equals(0, #warnings)
  end)

  it("stays quiet when the marker is off (nothing is reported as broken)", function()
    set_line(root .. "/gone.md")
    require("hover.switches").set("missing", false, { silent = true })
    hover.show({ force = true })
    assert.equals(0, #warnings)
  end)

  it("stays quiet for text the bare-path rules call ambiguous", function()
    set_line("see vim.api for it")
    hover.show({ force = true })
    assert.equals(0, #warnings)
  end)

  it("stays quiet for a target that exists", function()
    local real = root .. "/real.md"
    vim.fn.writefile({ "x" }, real)
    set_line(real)
    assert.is_true(hover.show({ force = true }))
    assert.equals(0, #warnings)
  end)
end)
