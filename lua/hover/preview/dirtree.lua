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
--- **A folder can be shown open in place**, its entries indented under it
--- (`dir_keys.expand`, no key by default: the listing is flat unless the
--- reader asks). That does not make the tree live in the float either:
--- `M.list` is told which folders are open and draws the listing again.
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
---@field lines string[] one per entry, then a last line that counts what was left out when there is more
---@field entries Hover.DirEntry[] what each of the first `#entries` lines stands for
---@field more boolean the last line is a count of what was left out, not an entry
---@field can_expand boolean the tree can show a folder open in place (`M.list` takes `expanded`)

--- The folder a "... N more" row of the tree counts for, or nil when the row does not say. The row has no
--- path: it names its folder in `dir`. A filetree.nvim from before that field says it only in the id of
--- the row, the folder's with `//more` behind it, which is no part of the contract and read as a fallback.
---@param row table
---@return string|nil
local function more_of(row)
  local folder = type(row.dir) == "string" and row.dir ~= "" and row.dir or nil
  if not folder and type(row.id) == "string" then
    folder = row.id:match("^(.+)//more$")
  end
  return folder and vim.fs.normalize(folder) or nil
end

--- List `dir` through the embedded tree.
---
--- `expanded` names folders below `dir` that are shown open, their entries indented under them. The tree is
--- still asked and let go in this one call: which folders are open is the caller's to remember, not a tree
--- that lives on. A name that is no folder of the listing (it is gone, or its parent is closed) is passed
--- over.
---@param dir string absolute directory path
---@param limit integer entries shown at most, per folder and in all
---@param expanded? string[] folders to show open
---@return Hover.DirTree.Listing|nil nil: no engine, or it could not list this directory; `dirbrowse` takes over
function M.list(dir, limit, expanded)
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
    local can_expand = type(tree.expand) == "function"
    if can_expand and type(expanded) == "table" and #expanded > 0 then
      -- a folder before what lies in it: a row exists only once its parent is open
      local wanted = vim.list_extend({}, expanded)
      table.sort(wanted, function(a, b)
        return #a < #b
      end)
      for _, path in ipairs(wanted) do
        if type(path) == "string" then
          tree:expand(path)
        end
      end
    end
    local rows = tree:rows()
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    tree:close()
    if #rows == 0 then
      listing = { lines = {}, entries = {}, more = false, can_expand = can_expand }
      return
    end
    -- one row, one line: anything else and the line a reader selects would not be the entry it resolves to
    if #rows ~= #lines then
      return
    end
    local top = vim.fs.normalize(dir)
    local entries, more, counted = {}, false, nil
    for i, row in ipairs(rows) do
      if row.kind == "more" or type(row.path) ~= "string" then
        local folder = more_of(row)
        if i == #rows and (folder == nil or folder == top) then
          -- what the listed directory itself has more of: the last line, and no entry
          more = true
          local n = row.more
          counted = type(n) == "number" and n >= 0 and n == math.floor(n) and n or nil
        elseif folder and folder ~= top then
          -- what a folder shown open has more of: a line to select, and it leads into that folder, where
          -- the rest is
          entries[#entries + 1] = { name = "…", path = folder, is_dir = true, more = true }
        else
          -- a line in the middle that stands for nothing: not a listing this float can select in
          return
        end
      else
        entries[#entries + 1] = {
          name = vim.fs.basename(row.path),
          path = row.path,
          is_dir = row.kind == "dir",
          expanded = row.expanded == true or nil,
        }
      end
    end
    -- The float is at most `limit` rows high, and the count of what is left needs a row of its own: a
    -- listing longer than that shows `limit - 1` entries and the count as its last row (appended as row
    -- `limit + 1` it was never on screen). Folders shown open add lines, the tree's own count of the
    -- directory adds one more.
    local keep = math.max(1, limit - 1)
    if #lines > limit and #entries > keep then
      -- what the tree counted for the directory itself is added; where it gave no number the count
      -- below is a floor, and says so
      local left = #entries - keep + (counted or 0)
      local cut_lines, cut_entries = {}, {}
      for i = 1, keep do
        cut_lines[i], cut_entries[i] = lines[i], entries[i]
      end
      cut_lines[#cut_lines + 1] = ((more and not counted) and "… %d+ more" or "… %d more"):format(
        left
      )
      lines, entries, more = cut_lines, cut_entries, true
    end
    listing = { lines = lines, entries = entries, more = more, can_expand = can_expand }
  end)
  pcall(api.nvim_buf_delete, buf, { force = true })
  if not ok then
    return nil
  end
  return listing
end

return M
