---@diagnostic disable: need-check-nil
-- The test body is the guard; see the note in TESTS/bare_path_spec.lua
-- (`LLS-42`).

-- TESTS/dirtree_spec.lua -- the directory hover drawn by filetree.nvim's own
-- tree, and by the plugin's own scan without it.
--
-- `hover.preview.dirtree` asks the `embed` layout of filetree.nvim for the
-- listing when that plugin is loaded, and answers nil otherwise, which hands
-- the directory back to `hover.preview.dirbrowse`. Both paths end in the same
-- content shape (`lines`, one `dir_entries` per line), so everything after it
-- -- selection, keys, click -- is one code path, checked elsewhere.
--
-- The seam is checked against a stand-in engine (what is asked of it, what a
-- broken answer falls back to, that nothing is left behind), and against the
-- real one where a filetree.nvim with `embed` is found ($FILETREE_NVIM_DIR);
-- a runner without it reports those cases as pending.

local dirtree = require("hover.preview.dirtree")
local text = require("hover.preview.text")

local uv = vim.uv or vim.loop

---@return integer
local function buffers()
  return #vim.api.nvim_list_bufs()
end

---@return integer
local function autocmds()
  return #vim.api.nvim_get_autocmds({})
end

---@return integer
local function watchers()
  local n = 0
  uv.walk(function(handle)
    local kind = handle:get_type()
    if (kind == "fs_event" or kind == "fs_poll" or kind == "timer") and not handle:is_closing() then
      n = n + 1
    end
  end)
  return n
end

---@param list Hover.DirEntry[]
---@return string[]
local function names(list)
  local out = {}
  for i, e in ipairs(list) do
    out[i] = e.name
  end
  return out
end

describe("hover.preview.dirtree", function()
  local root, kept

  before_each(function()
    root = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(root .. "/zeta", "p")
    vim.fn.mkdir(root .. "/Alpha", "p")
    vim.fn.writefile({}, root .. "/b.txt")
    vim.fn.writefile({}, root .. "/a.txt")
    kept = { package.loaded["filetree"], package.loaded["filetree.native"] }
    package.loaded["filetree"], package.loaded["filetree.native"] = nil, nil
  end)

  after_each(function()
    package.loaded["filetree"], package.loaded["filetree.native"] = kept[1], kept[2]
    vim.fn.delete(root, "rf")
  end)

  ---A stand-in for `filetree.native`: `embed` writes `lines` and answers a handle with `rows`.
  local function engine(lines, rows, seen)
    return {
      embed = function(buf, dir, opts)
        if seen then
          seen.buf, seen.dir, seen.opts = buf, dir, opts
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        return {
          rows = function()
            return rows
          end,
          close = function()
            if seen then
              seen.closed = (seen.closed or 0) + 1
            end
          end,
        }
      end,
    }
  end

  describe("without filetree.nvim", function()
    it("has no engine and lists nothing", function()
      assert.is_nil(dirtree.engine())
      assert.is_nil(dirtree.list(root, 20))
    end)

    it("does not load filetree.nvim to find out", function()
      -- a searcher that would see the require: none may arrive
      local asked = {}
      local function searcher(name)
        asked[#asked + 1] = name
        return nil
      end
      table.insert(package.loaders, 1, searcher)
      dirtree.list(root, 20)
      table.remove(package.loaders, 1)
      assert.same({}, asked)
    end)

    it("leaves the directory preview to the plugin's own scan", function()
      local content = text.directory({ path = root }, { max_lines = 20 })
      assert.same({ "Alpha/", "zeta/", "a.txt", "b.txt" }, content.lines)
      assert.same({ "Alpha", "zeta", "a.txt", "b.txt" }, names(content.dir_entries))
    end)

    it("treats a filetree.nvim without the embed layout as none", function()
      package.loaded["filetree.native"] = { open = function() end }
      assert.is_nil(dirtree.engine())
      assert.is_nil(dirtree.list(root, 20))
    end)
  end)

  describe("with an engine", function()
    it("asks it for the directory, bounded, without a selection or a watcher of its own", function()
      local seen = {}
      package.loaded["filetree.native"] = engine(
        { "x" },
        { { path = root .. "/x", kind = "file" } },
        seen
      )
      dirtree.list(root, 7)
      assert.equals(root, seen.dir)
      assert.equals(7, seen.opts.max_entries)
      assert.is_false(seen.opts.select)
      assert.is_false(seen.opts.watch)
      assert.equals(1, seen.closed)
    end)

    it("answers the tree's lines and one entry per line", function()
      package.loaded["filetree.native"] = engine({ " Alpha", " src/lua", " a.txt" }, {
        { path = root .. "/Alpha", kind = "dir" },
        { path = root .. "/src/lua", kind = "dir" },
        { path = root .. "/a.txt", kind = "file" },
      })
      local listing = dirtree.list(root, 20)
      assert.same({ " Alpha", " src/lua", " a.txt" }, listing.lines)
      assert.same({
        { name = "Alpha", path = root .. "/Alpha", is_dir = true },
        -- a chain of single folders is one line; it stands for the folder at its end
        { name = "lua", path = root .. "/src/lua", is_dir = true },
        { name = "a.txt", path = root .. "/a.txt", is_dir = false },
      }, listing.entries)
      assert.is_false(listing.more)
    end)

    it("keeps the tree's count of what did not fit as a last line that is no entry", function()
      package.loaded["filetree.native"] = engine({ "a.txt", "… 41 more" }, {
        { path = root .. "/a.txt", kind = "file" },
        { kind = "more" },
      })
      local listing = dirtree.list(root, 1)
      assert.same({ "a.txt", "… 41 more" }, listing.lines)
      assert.equals(1, #listing.entries)
      assert.is_true(listing.more)

      local content = text.directory({ path = root }, { max_lines = 1 })
      assert.same({ "a.txt", "… 41 more" }, content.lines)
      assert.equals(1, #content.dir_entries)
      assert.is_true(content.tail_marker)
    end)

    it("says so for an empty directory", function()
      package.loaded["filetree.native"] = engine({ "" }, {})
      local content = text.directory({ path = root }, { max_lines = 20 })
      assert.same({ "(empty directory)" }, content.lines)
      assert.same({}, content.dir_entries)
    end)

    it("falls back to the own scan when lines and rows do not match", function()
      package.loaded["filetree.native"] = engine(
        { "one", "two", "three" },
        { { path = root .. "/one", kind = "file" } }
      )
      assert.is_nil(dirtree.list(root, 20))
      local content = text.directory({ path = root }, { max_lines = 20 })
      assert.same({ "Alpha/", "zeta/", "a.txt", "b.txt" }, content.lines)
    end)

    it("falls back when a line in the middle is no entry", function()
      package.loaded["filetree.native"] = engine({ "… 3 more", "a.txt" }, {
        { kind = "more" },
        { path = root .. "/a.txt", kind = "file" },
      })
      assert.is_nil(dirtree.list(root, 20))
    end)

    it("falls back when the engine has no tree for the directory, or raises", function()
      package.loaded["filetree.native"] = {
        embed = function()
          return nil, "not a directory"
        end,
      }
      assert.is_nil(dirtree.list(root, 20))
      package.loaded["filetree.native"] = {
        embed = function()
          error("boom")
        end,
      }
      assert.is_nil(dirtree.list(root, 20))
      assert.same(
        { "Alpha/", "zeta/", "a.txt", "b.txt" },
        text.directory({ path = root }, { max_lines = 20 }).lines
      )
    end)

    it("leaves no buffer behind, whatever the engine did", function()
      local before = buffers()
      package.loaded["filetree.native"] = engine(
        { "x" },
        { { path = root .. "/x", kind = "file" } }
      )
      dirtree.list(root, 20)
      package.loaded["filetree.native"] = {
        embed = function()
          error("boom")
        end,
      }
      dirtree.list(root, 20)
      package.loaded["filetree.native"] = {
        embed = function()
          return nil, "no"
        end,
      }
      dirtree.list(root, 20)
      assert.equals(before, buffers())
    end)
  end)

  describe("with filetree.nvim's own tree", function()
    ---The real engine, or nil when no filetree.nvim with `embed` is around.
    local function real()
      local dir = vim.env.FILETREE_NVIM_DIR
      if not dir or dir == "" or vim.fn.isdirectory(dir .. "/lua/filetree/native") == 0 then
        return nil
      end
      vim.opt.runtimepath:append(dir)
      local ok, native = pcall(require, "filetree.native")
      if not ok or type(native) ~= "table" or type(native.embed) ~= "function" then
        package.loaded["filetree.native"] = nil
        vim.opt.runtimepath:remove(dir)
        return nil
      end
      return native, dir
    end

    it("draws the listing: folders first, a chain as one line, one entry per line", function()
      local native, dir = real()
      if not native then
        pending("no filetree.nvim with the embed layout here ($FILETREE_NVIM_DIR)")
        return
      end
      vim.fn.mkdir(root .. "/zeta/only/deep", "p")
      vim.fn.writefile({}, root .. "/zeta/only/deep/leaf.txt")

      local before = { buffers(), autocmds(), watchers() }
      local content = text.directory({ path = root }, { max_lines = 20 })
      local after = { buffers(), autocmds(), watchers() }

      assert.equals(#content.lines, #content.dir_entries)
      local dirs, files = {}, {}
      for _, e in ipairs(content.dir_entries) do
        table.insert(e.is_dir and dirs or files, e.name)
      end
      assert.same({ "a.txt", "b.txt" }, files)
      assert.equals(2, #dirs)
      -- folders stand before files
      assert.is_true(content.dir_entries[1].is_dir and content.dir_entries[2].is_dir)
      -- the chain zeta/only/deep is one line and stands for its last folder
      local chain
      for i, e in ipairs(content.dir_entries) do
        if e.path:find("zeta", 1, true) then
          chain = { line = content.lines[i], path = vim.fs.normalize(e.path) }
        end
      end
      assert.equals(root .. "/zeta/only/deep", chain.path)
      assert.is_truthy(chain.line:find("zeta/only/deep", 1, true))
      -- every entry is where it says it is
      for _, e in ipairs(content.dir_entries) do
        assert.is_truthy(uv.fs_stat(e.path))
      end
      -- nothing of the tree outlives the call
      assert.same(before, after)

      package.loaded["filetree.native"] = nil
      vim.opt.runtimepath:remove(dir)
    end)

    it("bounds a big directory and says how many more there are", function()
      local native, dir = real()
      if not native then
        pending("no filetree.nvim with the embed layout here ($FILETREE_NVIM_DIR)")
        return
      end
      for i = 1, 30 do
        vim.fn.writefile({}, ("%s/file_%02d.txt"):format(root, i))
      end
      local content = text.directory({ path = root }, { max_lines = 5 })
      assert.equals(5, #content.dir_entries)
      assert.equals(6, #content.lines)
      assert.is_true(content.tail_marker)
      assert.is_truthy(content.lines[6]:find("%d+"))

      package.loaded["filetree.native"] = nil
      vim.opt.runtimepath:remove(dir)
    end)
  end)
end)
