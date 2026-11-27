---@diagnostic disable: need-check-nil
-- The test body is the guard; see the note in TESTS/bare_path_spec.lua
-- (`LLS-42`).

-- TESTS/copy_spec.lua -- `:Hover copy`: what the float shows, taken out of a
-- window nothing can be selected in.
--
-- The clipboard is lib.nvim's `copy_to_clipboard`, stubbed here: on a runner
-- without a provider it would start a process the guards refuse, and what is
-- pinned is what this plugin hands over, not whether a clipboard exists.

local copy = require("hover.copy")

--- Run an asynchronous `fn(report)` and wait for its one answer.
---@param fn fun(report: fun(ok: boolean, message: string))
---@return boolean ok
---@return string message
local function answer(fn)
  local got
  fn(function(ok, message)
    assert.is_nil(got, "reported twice")
    got = { ok, message }
  end)
  assert.is_true(
    vim.wait(2000, function()
      return got ~= nil
    end, 5),
    "no answer"
  )
  return got[1], got[2]
end

--- A stand-in for lib.nvim's `copy_to_clipboard` that answers as the real one does:
--- never before it returned, always through `on_done`. Without the callback it
--- throws, as a blocking clipboard would freeze the editor.
---@param clipped string[]
---@param result boolean
---@return function
local function async_clip(clipped, result)
  return function(text, on_done)
    assert(on_done, "the clipboard was called in its blocking form")
    clipped[#clipped + 1] = text
    vim.schedule(function()
      on_done(result)
    end)
  end
end

describe("hover.copy", function()
  local saved_clip, saved_dir, dir
  ---@type string[]
  local clipped

  before_each(function()
    clipped = {}
    saved_clip = package.loaded["lib.nvim.cross.copy_to_clipboard"]
    package.loaded["lib.nvim.cross.copy_to_clipboard"] = async_clip(clipped, true)
    dir = vim.fn.tempname() .. "-copies"
    saved_dir = copy.dir
    copy.dir = function()
      return dir
    end
    copy.reset()
    vim.fn.setreg('"', "")
  end)

  after_each(function()
    package.loaded["lib.nvim.cross.copy_to_clipboard"] = saved_clip
    copy.dir = saved_dir
    vim.fn.delete(dir, "rf")
  end)

  it("drops the padding a preview ends with, and counts what is left", function()
    local text, count = copy.text({ "one", "", "two", "", "  " })
    assert.same("one\n\ntwo", text)
    assert.same(3, count)
    assert.same(0, select(2, copy.text({ "", "" })))
  end)

  it("puts the text into the unnamed register and onto the clipboard", function()
    local took
    copy.put("one\ntwo", true, function(clip)
      took = clip
    end)
    assert.same("one\ntwo\n", vim.fn.getreg('"'), "the register is set before put returns")
    assert.is_nil(took, "the clipboard answered before put returned")
    vim.wait(2000, function()
      return took ~= nil
    end, 5)
    assert.is_true(took)
    assert.same("V", vim.fn.getregtype('"'))
    -- With a newline on the clipboard: a provider keeps no register type, so
    -- under `clipboard=unnamedplus` that newline is what makes `p` linewise.
    assert.same({ "one\ntwo\n" }, clipped)
  end)

  it("does not wait for the clipboard: the register is set, the answer comes later", function()
    local pending
    package.loaded["lib.nvim.cross.copy_to_clipboard"] = function(_, on_done)
      pending = on_done
    end
    local message
    copy.take({ lines = { "a", "b" } }, function(_, m)
      message = m
    end)
    assert.same("a\nb\n", vim.fn.getreg('"'))
    assert.is_nil(message, "the message came before the clipboard answered")
    pending(false)
    assert.is_truthy(message:find("unnamed register", 1, true), message)
    assert.is_falsy(message:find("clipboard", 1, true), message)
  end)

  it("drops the marker a truncated preview ends on", function()
    assert.same({ "a", 1 }, { copy.text({ "a", "…" }, true) })
    assert.same({ "a", 1 }, { copy.text({ "a", "… (12 entries)", "" }, true) })
    assert.same({ "a …", 1 }, { copy.text({ "a …" }, true) })
  end)

  it("keeps a real last line of … when the preview was not truncated", function()
    assert.same({ "a\n…", 2 }, { copy.text({ "a", "…" }) })
    assert.same({ "a\n… (the end)", 2 }, { copy.text({ "a", "… (the end)", "" }) })
  end)

  it("drops only the one marker, not the real … line above it", function()
    assert.same({ "a\n…", 2 }, { copy.text({ "a", "…", "…" }, true) })
  end)

  it("refuses with the hover's own reason", function()
    local ok, message = answer(function(report)
      copy.take(
        { lines = { "████" }, refused = "a playing video has nothing to copy" },
        report
      )
    end)
    assert.is_false(ok)
    assert.same("a playing video has nothing to copy", message)
    assert.same({}, clipped)
  end)

  it("dates the copy now, not when the picture was made", function()
    -- `fs_copyfile` keeps the source's mtime; the sweep reads it.
    local source = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "old" }, source, "b")
    local month_ago = os.time() - 30 * 24 * 60 * 60
    vim.uv.fs_utime(source, month_ago, month_ago)
    local path = copy.picture(source, nil)
    assert.is_true(
      vim.uv.fs_stat(path).mtime.sec > os.time() - 60,
      "the copy is as old as its source"
    )
    copy.reset()
    copy.picture(source, nil)
    assert.is_truthy(vim.uv.fs_stat(path), "the next session's sweep took a fresh copy")
    vim.fn.delete(source)
  end)

  it("keeps credentials out of the name, and a # in a local path in it", function()
    local source = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "png" }, source, "b")
    local from_url = copy.picture(source, "https://alice:secret@example.com/")
    assert.is_falsy(from_url:find("secret", 1, true), from_url)
    local from_path = copy.picture(source, "/pics/issue#12.png")
    assert.is_truthy(vim.fs.basename(from_path):find("issue_12", 1, true), from_path)
    vim.fn.delete(source)
  end)

  it("says why when the copies directory cannot be made", function()
    local blocker = vim.fn.tempname()
    vim.fn.writefile({ "x" }, blocker)
    copy.dir = function()
      return blocker .. "/copies"
    end
    local source = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "png" }, source, "b")
    local path, err = copy.picture(source, nil)
    assert.is_nil(path)
    assert.is_truthy(err:find("could not make", 1, true), err)
    vim.fn.delete(source)
    vim.fn.delete(blocker)
  end)

  it("names the copy of a URL without a path after its host", function()
    local source = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "x" }, source, "b")
    local path = copy.picture(source, "https://example.com")
    assert.is_truthy(vim.fs.basename(path):match("^example%.com%-%d+%-%d+%.png$"), path)
    local slash = copy.picture(source, "https://example.com/?q=1")
    assert.is_truthy(vim.fs.basename(slash):match("^example%.com%-%d+%-%d+"), slash)
    local dir = copy.picture(source, "https://example.com/a.b/")
    assert.is_truthy(vim.fs.basename(dir):match("^a%.b%-%d+%-%d+%.png$"), dir)
    vim.fn.delete(source)
  end)

  it("copies the picture on screen into a file of its own, named after the target", function()
    local source = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "not really a png" }, source, "b")
    local path, err = copy.picture(source, "https://example.com/docs/guide.html?x=1")
    assert.is_nil(err)
    assert.is_truthy(path:find(dir, 1, true) == 1, path)
    assert.is_truthy(vim.fs.basename(path):match("^guide%-%d+%-%d+%.png$"), path)
    assert.same(vim.fn.readfile(source, "b"), vim.fn.readfile(path, "b"))

    local again = copy.picture(source, "https://example.com/docs/guide.html?x=1")
    assert.are_not.equal(path, again, "a second copy in the same second overwrote the first")
    vim.fn.delete(source)
  end)

  it("takes the picture over the blank lines a drawn hover is framed with", function()
    local source = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "png" }, source, "b")
    local ok, message = answer(function(report)
      copy.take({ image_path = source, lines = { "", "" }, hint = "/x/shot.png" }, report)
    end)
    assert.is_true(ok, message)
    local path = vim.fn.getreg('"')
    assert.is_truthy(path:find(dir, 1, true) == 1, path)
    assert.same({ path }, clipped, "the path, and only the path, went to the clipboard")
    assert.is_truthy(message:find(path, 1, true))
    vim.fn.delete(source)
  end)

  it("declines a hover with nothing in it", function()
    local ok, message = answer(function(report)
      copy.take({ lines = { "", " " } }, report)
    end)
    assert.is_false(ok)
    assert.is_truthy(message:find("nothing to copy", 1, true))
  end)

  it("says so when the picture is gone", function()
    local path, err = copy.picture(vim.fn.tempname() .. ".png", nil)
    assert.is_nil(path)
    assert.is_truthy(err:find("no longer on disk", 1, true))
  end)
end)

describe("hover.copy on a real float", function()
  local config = require("hover.config")
  local keys = require("hover.bindings.keymaps")
  local registry = require("hover.registry")
  local hover = require("hover")
  local root, win, prev_buf, buf, saved_clip, prev_isfname

  before_each(function()
    config.reset()
    registry.reset()
    keys.release()
    saved_clip = package.loaded["lib.nvim.cross.copy_to_clipboard"]
    package.loaded["lib.nvim.cross.copy_to_clipboard"] = async_clip({}, true)
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "first line", "second line", "third line" }, root .. "/three.txt")
    prev_isfname = vim.o.isfname
    vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"
    win = vim.api.nvim_get_current_win()
    prev_buf = vim.api.nvim_win_get_buf(win)
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, root .. "/notes.md")
    vim.api.nvim_win_set_buf(win, buf)
    vim.fn.setreg('"', "")
  end)

  after_each(function()
    hover.hide()
    keys.release()
    package.loaded["lib.nvim.cross.copy_to_clipboard"] = saved_clip
    pcall(vim.api.nvim_win_set_buf, win, prev_buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    vim.o.isfname = prev_isfname
    vim.fn.delete(root, "rf")
    config.reset()
    registry.reset()
  end)

  it("copies the lines on screen, without the title", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see ./three.txt here" })
    vim.api.nvim_win_set_cursor(win, { 1, 5 })
    assert.is_true(hover.show({ force = true }), "no hover opened")
    local ok, message = answer(hover.copy)
    assert.is_true(ok, message)
    local got = vim.fn.getreg('"')
    assert.is_truthy(got:find("first line\nsecond line\nthird line", 1, true), got)
    assert.is_falsy(got:find("three.txt", 1, true), "the title came along: " .. got)
  end)

  it("binds Y while a float is up, and hands it back after", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "see ./three.txt here" })
    vim.api.nvim_win_set_cursor(win, { 1, 5 })
    assert.is_true(hover.show({ force = true }))
    local m = vim.fn.maparg("Y", "n", false, true)
    assert.same("hover: copy what this hover shows", m.desc)
    hover.hide()
    local after = vim.fn.maparg("Y", "n", false, true)
    assert.are_not.equal("hover: copy what this hover shows", after.desc)
  end)

  it("says so when no hover is open", function()
    local ok, message = answer(hover.copy)
    assert.is_false(ok)
    assert.same("no hover to copy", message)
  end)
end)
