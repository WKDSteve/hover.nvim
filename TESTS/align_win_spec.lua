---@diagnostic disable: duplicate-set-field
-- TESTS/align_win_spec.lua -- `hover.preview.align_win.try_centre_new_window`
-- must not make the editor wait for `preview.monitor`'s answer (a PowerShell
-- start-up on Windows, 0.5-0.8 s): it asks in the background and starts the
-- alignment script once the answer is in. The script bodies themselves stay
-- untested here, same as in TESTS/monitor_spec.lua; `vim.system` is stubbed so
-- nothing real starts.

local align_win = require("hover.preview.align_win")

describe("hover.preview.align_win.try_centre_new_window", function()
  local real_system
  local spawned

  before_each(function()
    real_system = vim.system
    spawned = {}
    vim.system = function(argv)
      spawned[#spawned + 1] = argv
      return {
        wait = function()
          error("align_win waited on a process")
        end,
      }
    end
    package.loaded["hover.preview.monitor"] = nil
  end)

  after_each(function()
    vim.system = real_system
    package.loaded["hover.preview.monitor"] = nil
  end)

  it("asks the monitor in the background and starts the script only after the answer", function()
    -- Red before the fix: the blocking monitor.detect() was called, which
    -- this stub turns into an error, so the script never started.
    local pending_cb
    package.loaded["hover.preview.monitor"] = {
      detect = function()
        error("align_win called the blocking monitor.detect()")
      end,
      detect_async = function(cb)
        pending_cb = cb
      end,
    }

    align_win.try_centre_new_window()
    assert.is_not_nil(pending_cb, "the monitor was not asked")
    assert.are.equal(0, #spawned, "the alignment script started before the answer")

    pending_cb({ screen = 0, x = 10, y = 20, w = 800, h = 600 })
    assert.are.equal(1, #spawned)
  end)

  it("still starts the script when preview.monitor has no detect_async()", function()
    package.loaded["hover.preview.monitor"] = {}
    align_win.try_centre_new_window()
    assert.are.equal(1, #spawned)
  end)

  it("still starts the script when the monitor cannot answer", function()
    package.loaded["hover.preview.monitor"] = {
      detect_async = function(cb)
        cb(nil)
      end,
    }
    align_win.try_centre_new_window()
    assert.are.equal(1, #spawned)
  end)
end)
