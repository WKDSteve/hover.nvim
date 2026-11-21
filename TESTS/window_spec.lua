-- TESTS/window_spec.lua -- the mpv window `preview.video` hands off to.
--
-- What is worth a spec here is not "does mpv open" (that needs a real mpv
-- and a display, and media.nvim's own suite already covers `play_window`'s
-- argv) but what this module adds on top: it asks `preview.monitor` which
-- screen the terminal is on and passes that through, so mpv centres where the
-- reader actually is rather than always on screen 0 -- and it asks without
-- making the editor wait for the answer (a PowerShell start-up on Windows,
-- 0.5-0.8 s per `<CR>` while it was a synchronous `:wait()`).

local window = require("hover.preview.window")

---@param on_play fun(path: string, opts: table)|nil
local function stub_media(on_play)
  package.loaded["media"] = {
    play_window = function(path, opts)
      if on_play then
        on_play(path, opts)
      end
      return {
        stopped = function()
          return false
        end,
        stop = function() end,
      }
    end,
  }
end

--- A monitor whose answer arrives only when the test hands it over, and
--- whose blocking `detect` must never be called.
---@return { answer: fun(result: table|nil), asked: fun(): boolean }
local function stub_monitor_deferred()
  local pending_cb
  package.loaded["hover.preview.monitor"] = {
    detect = function()
      error("preview.window called the blocking monitor.detect()")
    end,
    detect_async = function(cb)
      pending_cb = cb
    end,
  }
  return {
    answer = function(result)
      pending_cb(result)
    end,
    asked = function()
      return pending_cb ~= nil
    end,
  }
end

describe("hover.preview.window", function()
  before_each(function()
    window.close()
    package.loaded["media"] = nil
    package.loaded["hover.preview.monitor"] = nil
  end)

  after_each(function()
    window.close()
  end)

  it("passes the detected screen through to media.play_window", function()
    local seen_opts
    stub_media(function(_, opts)
      seen_opts = opts
    end)
    local monitor = stub_monitor_deferred()

    local ok = window.open({ path = "/tmp/clip.mp4", at = 0 })
    assert.is_true(ok)
    monitor.answer({ screen = 1, x = 1920, y = 0, w = 1920, h = 1080 })
    assert.are.equal(1, seen_opts.screen)
  end)

  it("passes no screen when the terminal's monitor cannot be detected", function()
    local seen_opts
    stub_media(function(_, opts)
      seen_opts = opts
    end)
    local monitor = stub_monitor_deferred()

    local ok = window.open({ path = "/tmp/clip.mp4", at = 0 })
    assert.is_true(ok)
    monitor.answer(nil)
    assert.is_nil(seen_opts.screen)
  end)

  it("still opens fine when preview.monitor has no detect_async() to call", function()
    -- The type check is not decoration: an older or unexpected shape of this
    -- module must not turn every video hover into a crash the moment mpv
    -- would otherwise have played happily.
    local seen_opts
    stub_media(function(_, opts)
      seen_opts = opts
    end)
    package.loaded["hover.preview.monitor"] = {}

    local ok = window.open({ path = "/tmp/clip.mp4", at = 0 })
    assert.is_true(ok)
    assert.is_nil(seen_opts.screen)
  end)

  it("never waits for the monitor query: open returns before it answers", function()
    -- Red before the fix: open() called the blocking monitor.detect(), which
    -- this stub turns into an error, so mpv never opened.
    local played = 0
    stub_media(function()
      played = played + 1
    end)
    local monitor = stub_monitor_deferred()

    local ok = window.open({ path = "/tmp/clip.mp4", at = 0 })
    assert.is_true(ok)
    assert.is_true(monitor.asked(), "the monitor was not asked at all")
    assert.are.equal(0, played, "mpv opened before the monitor answered")
    assert.is_true(window.is_active(), "a window about to open must count as active")

    monitor.answer({ screen = 0, x = 0, y = 0, w = 800, h = 600 })
    assert.are.equal(1, played)
    assert.is_true(window.is_active())
  end)

  it("close() while the monitor is still answering cancels the open", function()
    -- `<CR>` again (or the hover closing) before the answer arrives: the late
    -- answer must not open a player nobody holds a handle to any more.
    local played = 0
    stub_media(function()
      played = played + 1
    end)
    local monitor = stub_monitor_deferred()

    window.open({ path = "/tmp/clip.mp4", at = 0 })
    window.close()
    assert.is_false(window.is_active())
    monitor.answer({ screen = 0, x = 0, y = 0, w = 800, h = 600 })
    assert.are.equal(0, played)
    assert.is_false(window.is_active())
  end)

  it("a newer open() wins over an older one whose answer arrives late", function()
    local paths = {}
    stub_media(function(path)
      paths[#paths + 1] = path
    end)
    local callbacks = {}
    package.loaded["hover.preview.monitor"] = {
      detect_async = function(cb)
        callbacks[#callbacks + 1] = cb
      end,
    }

    window.open({ path = "/tmp/first.mp4", at = 0 })
    window.open({ path = "/tmp/second.mp4", at = 0 })
    callbacks[2]({ screen = 0, x = 0, y = 0, w = 1, h = 1 })
    callbacks[1]({ screen = 0, x = 0, y = 0, w = 1, h = 1 })
    assert.same({ "/tmp/second.mp4" }, paths)
  end)

  it("warns instead of raising when mpv fails to start after the answer", function()
    package.loaded["media"] = {
      play_window = function()
        return nil, "mpv not found"
      end,
    }
    local monitor = stub_monitor_deferred()
    local real_notify = vim.notify
    local warned
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg, level)
      warned = { msg = msg, level = level }
    end

    local ok = window.open({ path = "/tmp/clip.mp4", at = 0 })
    local ok_answer = pcall(monitor.answer, nil)
    vim.notify = real_notify

    assert.is_true(ok)
    assert.is_true(ok_answer)
    assert.is_not_nil(warned)
    assert.matches("mpv not found", warned.msg)
    assert.are.equal(vim.log.levels.WARN, warned.level)
    assert.is_false(window.is_active())
  end)

  it("reports false at once when media.nvim has no windowed player", function()
    package.loaded["media"] = {}
    stub_monitor_deferred()
    local ok, err = window.open({ path = "/tmp/clip.mp4", at = 0 })
    assert.is_false(ok)
    assert.matches("no windowed player", err)
    assert.is_false(window.is_active())
  end)
end)
