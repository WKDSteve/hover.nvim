-- TESTS/sheets/_helpers.lua -- what the hover.nvim test sheets need in their child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's first step runs it with `dofile`, the child's cwd is the
-- project root. The directory is in the spec's @cache-inputs, so a change here re-runs the sheets.
--
-- The network is a stub (`_G.net_stub`): nothing is spawned and nothing connects, so the process guard of this
-- repository stays strict and `curl` never appears in `guard_allow`. The real transport is lib.nvim's to test
-- (its curl spec) and hover's auth spec; a sheet names it as a `manual` line.

local M = {}

vim.opt.shortmess:append("I")
vim.o.swapfile = false
vim.o.hidden = true

---A stand-in for lib.nvim.net.curl: `fetch_raw` answers from `answers[url]` (a table `{ status, status_text, headers,
---body }`, the shape the real one hands its callback) through vim.schedule, as the real one does from a process;
---every request is recorded in `_G.requests` as `{ url, request }`. An unknown URL is a curl that did not start
---(`ok = false`). Nothing is spawned, nothing connects. `fetch_raw` is the whole surface hover.preview.url uses
---(TESTS/url_spec.lua stubs the same one).
---@param answers table<string, table>
function _G.net_stub(answers)
  _G.requests = {}
  package.loaded["lib.nvim.net.curl"] = {
    fetch_raw = function(url, request, callback)
      _G.requests[#_G.requests + 1] = { url = url, request = request }
      vim.schedule(function()
        local a = answers[url]
        if a then
          callback(true, vim.deepcopy(a))
        else
          callback(false, {
            status = 0,
            status_text = "",
            headers = {},
            body = "",
            error = "no fixture for " .. url,
          })
        end
      end)
    end,
  }
end

---A fixture answer of TESTS/sheets/fixtures/http/.
---@param name string  the file name without `.lua`
---@return table
function _G.fixture(name)
  return dofile(vim.fn.getcwd() .. "/TESTS/sheets/fixtures/http/" .. name .. ".lua")
end

---The one floating window, or nil.
---@return integer|nil
function _G.float()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      return w
    end
  end
  return nil
end

---The windows that are not floats.
---@return integer[]
function _G.wins()
  return vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative == ""
  end, vim.api.nvim_list_wins())
end

---The lines of a buffer (default: the current one) as one string, joined by a newline.
---@param buf? integer
---@return string
function _G.text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false), "\n")
end

---What the float shows, as one string ("" without a float).
---@return string
function _G.float_text()
  local w = _G.float()
  return w and _G.text(vim.api.nvim_win_get_buf(w)) or ""
end

---`got == want`, or an error that says what came instead (the failure line of the sheet shows it).
---@param got any
---@param want any
---@return boolean
function _G.eq(got, want)
  if got ~= want then
    error(("got %s, wanted %s"):format(vim.inspect(got), vim.inspect(want)), 0)
  end
  return true
end

---`text` holds `part` (plain), or an error that shows the text.
---@param text string
---@param part string
---@return boolean
function _G.has(text, part)
  if not tostring(text):find(part, 1, true) then
    error(("no %s in %s"):format(vim.inspect(part), vim.inspect(text)), 0)
  end
  return true
end

---A temp dir (its real path: a runner's temp may be a short name or a link) as the child's cwd, in `_G.root`.
function _G.sandbox()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  _G.root = vim.fs.normalize(vim.uv.fs_realpath(dir))
  vim.fn.chdir(_G.root)
end

---Write `rel` below the sandbox and edit it.
---@param rel string
---@param ... string  the lines of the file
function _G.open(rel, ...)
  local path = _G.root .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ ... }, path)
  vim.cmd("edit! " .. vim.fn.fnameescape(path))
end

---Put the named sibling plugins on the runtimepath; false when one is not to be found. For `requires`.
---Looked up as `.testing.lua` does with `deps`: $<NAME>_DIR (alone when set), .deps/<name> (the CI's checkouts),
---../<name>, the lazy.nvim directory.
---@param ... string
---@return boolean
function M.add_deps(...)
  for _, name in ipairs({ ... }) do
    local env = vim.env[(name:upper():gsub("[^%w]", "_")) .. "_DIR"]
    local hit
    local data = vim.env.LOCALAPPDATA and (vim.env.LOCALAPPDATA .. "/nvim-data")
      or "~/.local/share/nvim"
    -- As TESTS/minimal_init.lua: an override that is set decides alone, a wrong one is never skipped.
    local places = (env and env ~= "") and { env }
      or { ".deps/" .. name, "../" .. name, vim.fn.expand(data) .. "/lazy/" .. name }
    for _, dir in ipairs(places) do
      if vim.fn.isdirectory(dir .. "/lua") == 1 then
        hit = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
        break
      end
    end
    if not hit then
      return false
    end
    vim.opt.rtp:append(hit)
  end
  return true
end

return M
