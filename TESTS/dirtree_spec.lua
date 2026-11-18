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
-- real one where a filetree.nvim with `embed` is found: $FILETREE_NVIM_DIR, or
-- the checkout TESTS/minimal_init.lua found (.deps/filetree.nvim in the CI, a
-- sibling otherwise). A runner without one reports those cases as pending.

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

    it("keeps the scan's summary on screen: one entry less, the summary as the last row", function()
      -- Alpha/, zeta/, a.txt, b.txt: four entries for three rows
      local content = text.directory({ path = root }, { max_lines = 3 })
      assert.same({ "Alpha/", "zeta/", "… (4 entries)" }, content.lines)
      assert.same({ "Alpha", "zeta" }, names(content.dir_entries))
      assert.is_true(content.tail_marker)
      -- one row: the summary alone, no entry
      local one = text.directory({ path = root }, { max_lines = 1 })
      assert.same({ "… (4 entries)" }, one.lines)
      assert.same({}, one.dir_entries)
      -- exactly as many entries as rows: no summary, nothing cut
      local fits = text.directory({ path = root }, { max_lines = 4 })
      assert.same({ "Alpha/", "zeta/", "a.txt", "b.txt" }, fits.lines)
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
      local listing = dirtree.list(root, 2)
      assert.same({ "a.txt", "… 41 more" }, listing.lines)
      assert.equals(1, #listing.entries)
      assert.is_true(listing.more)

      local content = text.directory({ path = root }, { max_lines = 2 })
      assert.same({ "a.txt", "… 41 more" }, content.lines)
      assert.equals(1, #content.dir_entries)
      assert.is_true(content.tail_marker)
    end)

    it("in a float one row high shows the count alone, which is then on screen", function()
      package.loaded["filetree.native"] = engine({ "a.txt", "… 41 more" }, {
        { path = root .. "/a.txt", kind = "file" },
        { kind = "more", more = 41 },
      })
      local listing = dirtree.list(root, 1)
      assert.same({ "… 42 more" }, listing.lines)
      assert.same({}, listing.entries)
      assert.is_true(listing.more)
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

  describe("a folder shown open in place", function()
    ---A stand-in for the tree that can open folders: `Alpha` holds `f1.txt`, a folder `sub` (with
    ---`g.txt`) and more than it shows; `a.txt` lies next to it. `seen.expand` notes what was asked.
    ---@param seen table
    ---@param opts? { expand?: boolean, bare_more?: boolean, top_more?: boolean, dir_field?: boolean }  `top_more`: the listed directory itself has more than the tree lists; `dir_field`: a count names its folder in `dir` and its id says nothing (the tree since that field)
    local function tree_engine(seen, opts)
      opts = opts or {}
      seen.expand, seen.closed, seen.embeds = {}, 0, 0
      return {
        embed = function(buf, dir)
          seen.embeds = seen.embeds + 1
          local open = {}
          local rows
          local function build()
            local lines = {}
            rows = {}
            local function add(line, row)
              lines[#lines + 1] = line
              rows[#rows + 1] = row
            end
            local alpha, sub = dir .. "/Alpha", dir .. "/Alpha/sub"
            add(
              "▸ Alpha/",
              { id = alpha, path = alpha, kind = "dir", expandable = true, expanded = open[alpha] }
            )
            if open[alpha] then
              add(
                "  ▸ sub/",
                { id = sub, path = sub, kind = "dir", expandable = true, expanded = open[sub] }
              )
              if open[sub] then
                add("      g.txt", { id = sub .. "/g.txt", path = sub .. "/g.txt", kind = "file" })
              end
              add(
                "    f1.txt",
                { id = alpha .. "/f1.txt", path = alpha .. "/f1.txt", kind = "file" }
              )
              if opts.dir_field then
                add("    … 3 more", { id = "more:1", kind = "more", dir = alpha, more = 3 })
              else
                add(
                  "    … 3 more",
                  { id = opts.bare_more and "?" or (alpha .. "//more"), kind = "more" }
                )
              end
            end
            add("  a.txt", { id = dir .. "/a.txt", path = dir .. "/a.txt", kind = "file" })
            if opts.top_more and opts.dir_field then
              add("  … 7 more", { id = "more:2", kind = "more", dir = dir, more = 7 })
            elseif opts.top_more then
              add("  … 7 more", { id = dir .. "//more", kind = "more" })
            end
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          end
          build()
          local handle = {
            rows = function()
              return rows
            end,
            close = function()
              seen.closed = seen.closed + 1
            end,
          }
          if opts.expand ~= false then
            function handle:expand(path)
              seen.expand[#seen.expand + 1] = path
              for _, row in ipairs(rows) do
                if row.path == path and row.kind == "dir" and not open[path] then
                  open[path] = true
                  build()
                  return true
                end
              end
              return false
            end
          end
          return handle
        end,
      }
    end

    it("is flat unless a folder is named, and says that it could", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen)
      local listing = dirtree.list(root, 20)
      assert.same({ "▸ Alpha/", "  a.txt" }, listing.lines)
      assert.same({ "Alpha", "a.txt" }, names(listing.entries))
      assert.is_true(listing.can_expand)
      assert.same({}, seen.expand)
      assert.is_nil(listing.entries[1].expanded)
    end)

    it("opens the named folders, a folder before what lies in it", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen)
      -- the child is named first, and a folder that is not there
      local listing =
        dirtree.list(root, 20, { root .. "/Alpha/sub", root .. "/gone", root .. "/Alpha" })
      assert.same({ root .. "/gone", root .. "/Alpha", root .. "/Alpha/sub" }, seen.expand)
      assert.same(
        { "▸ Alpha/", "  ▸ sub/", "      g.txt", "    f1.txt", "    … 3 more", "  a.txt" },
        listing.lines
      )
      assert.equals(#listing.lines, #listing.entries)
      assert.same({ "Alpha", "sub", "g.txt", "f1.txt", "…", "a.txt" }, names(listing.entries))
      assert.is_true(listing.entries[1].expanded)
      assert.is_true(listing.entries[2].expanded)
      assert.is_nil(listing.entries[3].expanded)
      assert.is_false(listing.more)
      assert.equals(1, seen.closed)
    end)

    it("makes the count of an open folder a line that leads into that folder", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen)
      local listing = dirtree.list(root, 20, { root .. "/Alpha" })
      local more = listing.entries[4]
      assert.equals("    … 3 more", listing.lines[4])
      assert.is_true(more.more)
      assert.is_true(more.is_dir)
      assert.equals(root .. "/Alpha", more.path)
    end)

    it("still shows no more entries than the float has room for", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen)
      local listing = dirtree.list(root, 3, { root .. "/Alpha", root .. "/Alpha/sub" })
      -- three rows: two entries and the count of the four left
      assert.equals(2, #listing.entries)
      -- the cut takes Alpha's own "… 3 more" line, which stands for three: a floor
      assert.same({ "▸ Alpha/", "  ▸ sub/", "… 4+ more" }, listing.lines)
      assert.is_true(listing.more)
    end)

    it("counts a floor where the cut takes the count of the directory itself away", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen, { top_more = true })
      -- flat: the count of the tree is the last line, as it wrote it
      local flat = dirtree.list(root, 3)
      assert.same({ "▸ Alpha/", "  a.txt", "  … 7 more" }, flat.lines)
      assert.is_true(flat.more)
      -- a folder open: five entries for three rows, and seven more nobody gave a number for
      local listing = dirtree.list(root, 3, { root .. "/Alpha" })
      assert.equals(2, #listing.entries)
      assert.equals(3, #listing.lines)
      assert.equals("… 3+ more", listing.lines[3])
      assert.is_true(listing.more)
    end)

    it(
      "keeps the count a floor when the cut takes the count line of a folder shown open",
      function()
        local seen = {}
        package.loaded["filetree.native"] = tree_engine(seen, { dir_field = true, top_more = true })
        -- Alpha/, sub/, f1.txt, "… 3 more" of Alpha, a.txt and the tree's "… 7 more": the cut takes the
        -- line of Alpha's three, which counts as one here, so the 10 is at least 10
        local listing = dirtree.list(root, 3, { root .. "/Alpha" })
        assert.same({ "▸ Alpha/", "  ▸ sub/", "… 10+ more" }, listing.lines)
      end
    )

    it("adds the tree's own count of the directory when the cut takes its line", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen, { dir_field = true, top_more = true })
      -- flat: Alpha/, a.txt and the tree's "… 7 more" are three lines for two rows
      local listing = dirtree.list(root, 2)
      assert.same({ "▸ Alpha/", "… 8 more" }, listing.lines)
      assert.equals(1, #listing.entries)
      assert.is_true(listing.more)
    end)

    it("reads the folder of a count from its dir field, whatever its id says", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen, { dir_field = true, top_more = true })
      local listing = dirtree.list(root, 20, { root .. "/Alpha" })
      local more = listing.entries[4]
      assert.equals("    … 3 more", listing.lines[4])
      assert.is_true(more.more)
      assert.equals(root .. "/Alpha", more.path)
      -- the count of the listed directory itself is still the last line and no entry
      assert.equals(5, #listing.entries)
      assert.equals("  … 7 more", listing.lines[6])
      assert.is_true(listing.more)
    end)

    it("takes the dir field over an id that names another folder", function()
      local seen = {}
      local engine = tree_engine(seen)
      local embed = engine.embed
      engine.embed = function(buf, dir)
        local handle = embed(buf, dir)
        local rows = handle.rows
        handle.rows = function()
          local out = rows()
          for _, row in ipairs(out) do
            if row.kind == "more" then
              row.id, row.dir = dir .. "/elsewhere//more", dir .. "/Alpha"
            end
          end
          return out
        end
        return handle
      end
      package.loaded["filetree.native"] = engine
      local listing = dirtree.list(root, 20, { root .. "/Alpha" })
      assert.equals(root .. "/Alpha", listing.entries[4].path)
    end)

    it("hands a count it cannot place back to the own scan", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen, { bare_more = true })
      assert.is_nil(dirtree.list(root, 20, { root .. "/Alpha" }))
    end)

    it("stays flat with a tree that cannot open folders", function()
      local seen = {}
      package.loaded["filetree.native"] = tree_engine(seen, { expand = false })
      local listing = dirtree.list(root, 20, { root .. "/Alpha" })
      assert.same({ "▸ Alpha/", "  a.txt" }, listing.lines)
      assert.is_false(listing.can_expand)
    end)

    describe("in the hover", function()
      local config = require("hover.config")
      local keys = require("hover.bindings.keymaps")
      local float = require("hover.float")
      local registry = require("hover.registry")
      local hover = require("hover")
      local win, prev_buf, prev_isfname, buf, seen

      ---@param lhs string
      ---@return boolean
      local function mapped(lhs)
        local m = vim.fn.maparg(lhs, "n", false, true)
        return type(m) == "table" and m.lhs ~= nil
      end

      ---@return string[]
      local function shown()
        return vim.api.nvim_buf_get_lines(assert(float.buf(), "no float is open"), 0, -1, false)
      end

      ---Show the hover on the directory `root`.
      ---@return boolean
      local function show()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see " .. root .. " here" })
        vim.api.nvim_win_set_cursor(win, { 1, 6 })
        return hover.show({ force = true })
      end

      ---What a cursor move does to the float.
      local function move_away()
        vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
      end

      before_each(function()
        config.reset()
        registry.reset()
        keys.release()
        vim.g.hover_disable = nil
        seen = {}
        win = vim.api.nvim_get_current_win()
        prev_buf = vim.api.nvim_win_get_buf(win)
        prev_isfname = vim.o.isfname
        vim.o.isfname = "@,48-57,/,\\,.,-,_,+,,,#,$,%,~,=,:"
        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(win, buf)
      end)

      after_each(function()
        hover.hide()
        keys.release()
        pcall(vim.api.nvim_win_set_buf, win, prev_buf)
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        vim.o.isfname = prev_isfname
        config.reset()
        registry.reset()
      end)

      it("borrows no key for it by default: the listing is flat", function()
        package.loaded["filetree.native"] = tree_engine(seen)
        assert.is_true(show())
        assert.same({ "▸ Alpha/", "  a.txt" }, shown())
        assert.same({}, keys.keylist(config.get().dir_keys.expand))
        assert.same({}, seen.expand)
      end)

      it("opens the selected folder under it and closes it again", function()
        package.loaded["filetree.native"] = tree_engine(seen)
        config.setup({ dir_keys = { expand = "o" } })
        assert.is_true(show())
        assert.is_true(mapped("o"), "the configured key is borrowed while the listing is up")

        assert.is_true(hover.dir_expand())
        assert.same(
          { "▸ Alpha/", "  ▸ sub/", "    f1.txt", "    … 3 more", "  a.txt" },
          shown()
        )

        -- the selection stayed on the folder: one line down is what lies in it
        assert.is_true(hover.dir_nav(0, 1))
        assert.is_true(hover.dir_expand())
        assert.same(
          { "▸ Alpha/", "  ▸ sub/", "      g.txt", "    f1.txt", "    … 3 more", "  a.txt" },
          shown()
        )

        -- a file has nothing to open
        assert.is_true(hover.dir_nav(0, 1))
        assert.is_false(hover.dir_expand())

        -- closing the outer folder takes what was open in it along
        assert.is_true(hover.dir_nav(0, -1))
        assert.is_true(hover.dir_nav(0, -1))
        assert.is_true(hover.dir_expand())
        assert.same({ "▸ Alpha/", "  a.txt" }, shown())
        assert.is_true(hover.dir_expand())
        assert.same(
          { "▸ Alpha/", "  ▸ sub/", "    f1.txt", "    … 3 more", "  a.txt" },
          shown()
        )
      end)

      it("steps into the folder from the line that counts what it has more of", function()
        package.loaded["filetree.native"] = tree_engine(seen)
        assert.is_true(show())
        assert.is_true(hover.dir_expand())
        for _ = 1, 3 do
          hover.dir_nav(0, 1)
        end
        assert.is_false(hover.dir_expand(), "the count is no folder to open")
        local embeds = seen.embeds
        assert.is_true(hover.dir_nav(1, 0))
        assert.equals(embeds + 1, seen.embeds, "the hover lists the folder itself now")
      end)

      it("leaves nothing behind when the float goes on a cursor move", function()
        package.loaded["filetree.native"] = tree_engine(seen)
        config.setup({ dir_keys = { expand = "o" } })
        -- once without, for what a hover leaves by itself
        assert.is_true(show())
        move_away()
        assert.is_nil(float.win())
        local before = { buffers(), autocmds(), watchers() }

        assert.is_true(show())
        assert.is_true(hover.dir_expand())
        hover.dir_nav(0, 1)
        assert.is_true(hover.dir_expand())
        move_away()
        assert.is_nil(float.win(), "the cursor move takes the float away")
        assert.is_false(mapped("o"), "and the borrowed key with it")
        assert.same(before, { buffers(), autocmds(), watchers() })
        assert.equals(seen.embeds, seen.closed, "every tree that was asked was let go")

        -- the next hover starts flat: what was open belonged to the float that went
        assert.is_true(show())
        assert.same({ "▸ Alpha/", "  a.txt" }, shown())
      end)

      it("does not borrow the key where the own scan drew the listing", function()
        config.setup({ dir_keys = { expand = "o" } })
        assert.is_true(show())
        assert.is_false(mapped("o"))
        assert.is_false(hover.dir_expand())
      end)
    end)
  end)

  describe("with filetree.nvim's own tree", function()
    ---The real engine, or nil when no filetree.nvim with `embed` is around.
    ---Where to look: `$FILETREE_NVIM_DIR` decides alone when it is set; otherwise the checkout
    ---`TESTS/minimal_init.lua` found (`.deps/filetree.nvim` in the CI, a sibling at a desk). That
    ---file keeps filetree.nvim off the runtimepath of the specs and hands the variable to the test
    ---sheets only, so a spec that read nothing but the variable never saw the checkout of the CI.
    local function real()
      local dir = vim.env.FILETREE_NVIM_DIR
      if not dir or dir == "" then
        dir = vim.g.hover_sheets_filetree_nvim
      end
      if
        type(dir) ~= "string"
        or dir == ""
        or vim.fn.isdirectory(dir .. "/lua/filetree/native") == 0
      then
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
        pending(
          "no filetree.nvim with the embed layout here ($FILETREE_NVIM_DIR, .deps, a sibling)"
        )
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
        pending(
          "no filetree.nvim with the embed layout here ($FILETREE_NVIM_DIR, .deps, a sibling)"
        )
        return
      end
      for i = 1, 30 do
        vim.fn.writefile({}, ("%s/file_%02d.txt"):format(root, i))
      end
      local content = text.directory({ path = root }, { max_lines = 5 })
      -- five rows: four entries and the count, which is on screen (as row six it never was)
      assert.equals(4, #content.dir_entries)
      assert.equals(5, #content.lines)
      assert.is_true(content.tail_marker)
      -- 34 entries (Alpha/, zeta/, a.txt, b.txt and 30 files), four of them shown
      assert.equals("… 30 more", content.lines[5])

      package.loaded["filetree.native"] = nil
      vim.opt.runtimepath:remove(dir)
    end)

    it("shows a folder open in place, and lets the tree go all the same", function()
      local native, dir = real()
      if not native then
        pending(
          "no filetree.nvim with the embed layout here ($FILETREE_NVIM_DIR, .deps, a sibling)"
        )
        return
      end
      vim.fn.mkdir(root .. "/zeta/sub", "p")
      vim.fn.writefile({}, root .. "/zeta/sub/leaf.txt")
      vim.fn.writefile({}, root .. "/zeta/inside.txt")

      local before = { buffers(), autocmds(), watchers() }
      local flat = text.directory({ path = root }, { max_lines = 20 })
      local open = text.directory(
        { path = root },
        { max_lines = 20, dir_expanded = { root .. "/zeta/sub", root .. "/zeta" } }
      )
      local after = { buffers(), autocmds(), watchers() }

      assert.is_true(flat.dir_expandable)
      assert.same({ "Alpha", "zeta", "a.txt", "b.txt" }, names(flat.dir_entries))
      assert.same(
        { "Alpha", "zeta", "sub", "leaf.txt", "inside.txt", "a.txt", "b.txt" },
        names(open.dir_entries)
      )
      assert.equals(#open.lines, #open.dir_entries)
      assert.is_true(open.dir_entries[2].expanded)
      assert.is_true(open.dir_entries[3].expanded)
      -- what lies in a folder stands further right than the folder
      local function indent(i)
        return #open.lines[i]:match("^%s*")
      end
      assert.is_true(indent(5) > indent(1))
      for _, e in ipairs(open.dir_entries) do
        assert.is_truthy(uv.fs_stat(e.path))
      end
      assert.same(before, after)

      package.loaded["filetree.native"] = nil
      vim.opt.runtimepath:remove(dir)
    end)

    it("counts what an open folder has more of on a line that leads into it", function()
      local native, dir = real()
      if not native then
        pending(
          "no filetree.nvim with the embed layout here ($FILETREE_NVIM_DIR, .deps, a sibling)"
        )
        return
      end
      for i = 1, 9 do
        vim.fn.writefile({}, ("%s/zeta/file_%d.txt"):format(root, i))
      end
      local content = text.directory(
        { path = root },
        { max_lines = 6, dir_expanded = { root .. "/zeta" } }
      )
      local more
      for i, e in ipairs(content.dir_entries) do
        if e.more then
          more = { entry = e, line = content.lines[i] }
        end
      end
      -- the cut of the float may take the line away; where it is there it leads into the folder
      if more then
        assert.equals(root .. "/zeta", vim.fs.normalize(more.entry.path))
        assert.is_truthy(more.line:find("%d+"))
      end
      assert.is_true(#content.dir_entries <= 6)
      assert.is_true(content.tail_marker)

      package.loaded["filetree.native"] = nil
      vim.opt.runtimepath:remove(dir)
    end)
  end)
end)
