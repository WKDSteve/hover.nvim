---@module 'hover.preview.window'
---@brief The `<CR>` on a video hover, when playback means a real mpv window
--- rather than a run of stills painted into the float.
---@description
--- **Why this exists next to `preview.playback`.** That module turns a decode
--- into moving block graphics inside the float — every frame is
--- `nvim_buf_set_extmark` calls, and the picture is the editor's redraw twelve
--- times a second. On a fast terminal it is smooth; on Windows in WezTerm it
--- was measured at about one repaint a second however the paint was written
--- (buffer lines, then extmarks, then overlay virtual text — three rewrites,
--- one slideshow), because the ceiling is the redraw, not the Lua.
---
--- So `video.playback = "window"` (the default) sends `<CR>` here instead:
--- `media.play_window` opens mpv with a window and the video on, and this holds
--- the handle that stops it again. mpv decodes, scales and syncs the sound
--- itself, with no editor redraw in the loop — the float meanwhile shows a
--- short "playing" panel rather than a picture, because there is no picture in
--- it to show.
---
--- **Single-instance, like the float.** There is one hover and one window it
--- speaks for; opening a second closes the first. `M.close` is registered as
--- the float's `on_close`, so the window goes away however the hover does — a
--- cursor move, `q`, `:qa` — and `media.core.player` has its own `VimLeavePre`
--- backstop under that for the exit that runs no `on_close` at all.

local M = {}

--- The one live window, or nil. `Media.Player.Handle` — `stop()` is idempotent
--- and ends the process tree, `stopped()` says whether it already ran.
---@type Media.Player.Handle|nil
local handle = nil

--- The open that is still waiting for `preview.monitor`'s answer, or nil.
--- A fresh table per `M.open`: the answer only starts mpv while this is still
--- the same table, so a `M.close` (or a newer `M.open`) in the meantime
--- cancels it.
---@type table|nil
local pending = nil

--- Whether a window this module opened is still playing, or about to open.
---@return boolean
function M.is_active()
  if pending ~= nil then
    return true
  end
  return handle ~= nil and not handle.stopped()
end

---@param media table
---@param spec { path: string, at: number|string|nil }
---@param detected { screen: integer|nil }|nil
---@return boolean ok
---@return string|nil err
local function start(media, spec, detected)
  local ok_play, h, err = pcall(media.play_window, spec.path, {
    at = spec.at,
    screen = detected and detected.screen or nil,
  })
  if not ok_play then
    return false, tostring(h)
  end
  if not h then
    return false, err or "mpv could not be started"
  end
  handle = h
  return true, nil
end

--- Open `spec.path` in an mpv window from `spec.at`, replacing any window
--- already open. Returns false plus a reason when media.nvim has no windowed
--- player at all -- the caller then falls back to the still, exactly as it
--- does for a failed decode. Otherwise it returns true at once and mpv opens
--- once `preview.monitor` has said where the terminal is; an mpv that then
--- fails to start is reported with a warning.
---@param spec { path: string, at: number|string|nil }
---@return boolean ok
---@return string|nil err
function M.open(spec)
  M.close()

  local ok_media, media = pcall(require, "media")
  if not ok_media or type(media.play_window) ~= "function" then
    return false, "media.nvim has no windowed player — update it"
  end

  -- Which monitor the terminal is on right now, so mpv's `--geometry`
  -- centres there instead of on screen 0 (see `preview.monitor`'s own doc
  -- for why this is safe to assume and why it is Windows-only for the index
  -- itself, not just the bounds). Asked in the background: on Windows the
  -- answer is a PowerShell start-up, 0.5-0.8 s that used to freeze the
  -- editor on every `<CR>`. Both `require` and the call are guarded: an
  -- unexpected shape of the module must not turn "mpv would have played
  -- happily" into a crash -- mpv then opens without a screen, as before this
  -- module existed.
  local ok_mon, monitor = pcall(require, "hover.preview.monitor")
  if not (ok_mon and type(monitor) == "table" and type(monitor.detect_async) == "function") then
    return start(media, spec, nil)
  end

  local this = {}
  pending = this
  local ok_ask = pcall(monitor.detect_async, function(detected)
    if pending ~= this then
      return
    end
    pending = nil
    local ok, err = start(media, spec, detected)
    if not ok then
      vim.notify("hover.nvim: " .. (err or "mpv could not be started"), vim.log.levels.WARN)
    end
  end)
  if not ok_ask then
    pending = nil
    return start(media, spec, nil)
  end
  return true, nil
end

--- Stop the window, if there is one, or cancel the one about to open. Safe
--- to call repeatedly, and from a teardown path — it never raises.
---@return nil
function M.close()
  pending = nil
  if handle then
    pcall(handle.stop)
    handle = nil
  end
end

return M
