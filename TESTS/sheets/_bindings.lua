-- TESTS/sheets/_bindings.lua -- hover.nvim as the nvim config sets it up, for the bindings sheets (the :Hover items of
-- the nvim config's docs/ROADMAP/Final_Checks/BINDINGS-RUNTIME-CHECKLIST.md). Not a sheet; a sheet's first step runs
-- it with `dofile` after _helpers.lua.
--
-- The config's spec (lua/plugins/personal/specs/navigate.lua of the nvim config, 2026-11-16): every option on hover's
-- own defaults except the video choices below, then `require("hover").enable()`. `persist` stays on as there: the
-- child's XDG directories are its own sandbox (testing.child.env), so nothing is written where a person's state is.
-- Messages are recorded instead of shown (`_G.notes`); lib.nvim's notify ends in vim.notify, partly scheduled, so a
-- sheet waits for a message rather than expecting it at once.

vim.o.laststatus = 0
vim.o.ruler = false
-- as in a real config: hover attaches its trigger to a buffer on FileType
vim.cmd("filetype on")

_G.notes = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  _G.notes[#_G.notes + 1] = tostring(msg)
end

---Whether a message containing `text` was recorded since the last `forget`.
---@param text string
---@return boolean
function _G.noted(text)
  for i = #_G.notes, 1, -1 do
    if _G.notes[i]:find(text, 1, true) then
      return true
    end
  end
  return false
end

---Drop the recorded messages.
function _G.forget()
  _G.notes = {}
end

---The state of a switch (`hover.switches`).
---@param name string
---@return boolean
function _G.sw(name)
  return require("hover.switches").enabled(name)
end

---The config of the floating window, or nil.
---@return table|nil
function _G.float_config()
  local w = _G.float()
  return w and vim.api.nvim_win_get_config(w) or nil
end

require("hover").setup({
  video = {
    use_mpv = false,
    experimental = {
      system_player_align = true,
      system_player_prefer_classic = true,
      system_player_search_installs = true,
    },
  },
})
require("hover").enable()
