---@module 'hover.preview.dirtree'
---@brief A directory listing drawn by filetree.nvim's own tree (its `embed` layout), when that tree is there.
---@description
--- `hover.preview.dirbrowse` was written as the seam for this: the mini
--- filetree of a directory hover needs a scan, an order and a line per entry,
--- and filetree.nvim now has an engine that can be asked for exactly that
--- without a window of its own (`require("filetree.native").embed`). So when
--- the plugin is loaded, the listing is the tree's: its order (folders first,
--- names without regard to case), its icons, a chain of single folders
--- `a/b/c` as one line, and its line for what did not fit.
---
--- **The tree is asked and let go in one call.** It draws into a scratch
--- buffer that exists for the length of `M.list`; the lines and the rows are
--- read off, the handle is closed, the buffer wiped. What reaches the float
--- is plain lines plus one `Hover.DirEntry` per line, the same shape
--- `dirbrowse` answers with, so the selection, the keys, the click and "which
--- window does a file open into" stay `hover.init`'s, unchanged. Nothing of
--- the tree outlives the call: no buffer, no watcher (`watch = false`), no
--- autocmd (the embed creates none), no key.
---
--- **Soft.** filetree.nvim is never loaded for this: the module is used only
--- when the plugin is already in `package.loaded`. A `require` of it would
--- make a plugin manager load and set it up on the spot, for a hover. Without
--- it, with an older one that has no `embed`, or when anything here fails,
--- `M.list` answers nil and `dirbrowse` draws as before.
---@see hover.preview.dirbrowse

local M = {}

local api = vim.api

--- The module that embeds the tree, or nil: filetree.nvim is not loaded, or
--- it is one without the `embed` layout.
---@return table|nil native
function M.engine()
  if package.loaded["filetree"] == nil and package.loaded["filetree.native"] == nil then
    return nil
  end
  local ok, native = pcall(require, "filetree.native")
  if ok and type(native) == "table" and type(native.embed) == "function" then
    return native
  end
  return nil
end

---@class Hover.DirTree.Listing
---@field lines string[] one per entry, then the tree's own "... N more" line when the directory has more
---@field entries Hover.DirEntry[] what each of the first `#entries` lines stands for
---@field more boolean the last line is the tree's count of what was left out, not an entry

--- List `dir` through the embedded tree.
---@param dir string absolute directory path
---@param limit integer entries shown at most
---@return Hover.DirTree.Listing|nil nil: no engine, or it could not list this directory; `dirbrowse` takes over
function M.list(dir, limit)
  local native = M.engine()
  if not native then
    return nil
  end
  local buf = api.nvim_create_buf(false, true)
  local listing
  local ok = pcall(function()
    local tree = native.embed(buf, dir, {
      max_entries = limit,
      select = false,
      watch = false,
    })
    if not tree then
      return
    end
    local rows = tree:rows()
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    tree:close()
    if #rows == 0 then
      listing = { lines = {}, entries = {}, more = false }
      return
    end
    -- one row, one line: anything else and the line a reader selects would not be the entry it resolves to
    if #rows ~= #lines then
      return
    end
    local entries, more = {}, false
    for i, row in ipairs(rows) do
      if row.kind == "more" or type(row.path) ~= "string" then
        -- the count of what was left out is the last line or the listing is not one this float can select in
        if i ~= #rows then
          return
        end
        more = true
      else
        entries[#entries + 1] = {
          name = vim.fs.basename(row.path),
          path = row.path,
          is_dir = row.kind == "dir",
        }
      end
    end
    listing = { lines = lines, entries = entries, more = more }
  end)
  pcall(api.nvim_buf_delete, buf, { force = true })
  if not ok then
    return nil
  end
  return listing
end

return M
