---@diagnostic disable: need-check-nil
-- The test body is the guard; see the note in TESTS/bare_path_spec.lua
-- (`LLS-42`).

-- TESTS/md_link_spec.lua -- the text of a markdown link is a hover target
-- without markdown.nvim (found 2026-11-16 by the casedesk sheet
-- `casedesk.hover-case-links`: on `[Log.txt](../assets/.../Log.txt)` the
-- cursor on `Log.txt` in the brackets found nothing).

local hover = require("hover")
local md_link = require("hover.md_link")

--- A markdown buffer named `<dir>/Swarm/notes.md` holding `lines`, current,
--- with the cursor at (row, col).
local function note(lines, row, col, ft)
  local dir = (vim.fn.tempname():gsub("\\", "/"))
  vim.fn.mkdir(dir .. "/Swarm", "p")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, dir .. "/Swarm/notes.md")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft or "markdown"
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { row, col })
  return buf, dir
end

describe("hover.md_link", function()
  before_each(function()
    hover.setup({})
  end)

  it("takes the target of an inline link with the cursor on its text", function()
    local buf = note({ "Log: [Log.txt](../assets/01_2026-11-16/Log.txt)" }, 1, 7)
    local found = hover.target_under_cursor(buf)
    assert.is_not_nil(found)
    assert.equals("../assets/01_2026-11-16/Log.txt", found.target)
    assert.equals("md_link", found.kind)
  end)

  it("answers the same on the target part and on the brackets", function()
    local line = "Log: [Log.txt](../assets/01_2026-11-16/Log.txt)"
    for _, col in ipairs({ 5, 13, 14, 30, #line - 1 }) do
      local buf = note({ line }, 1, col)
      local found = md_link.under_cursor(buf)
      assert.is_not_nil(found, "col " .. col)
      assert.equals("../assets/01_2026-11-16/Log.txt", found.target)
      assert.equals(5, found.col)
      assert.equals(#line - 1, found.col_end)
    end
  end)

  it("is nothing outside the link", function()
    local buf = note({ "Log: [Log.txt](a.txt) after" }, 1, 1)
    assert.is_nil(md_link.under_cursor(buf))
    vim.api.nvim_win_set_cursor(0, { 1, 24 })
    assert.is_nil(md_link.under_cursor(buf))
  end)

  it("resolves the target relative to the note, like the path part", function()
    local _, dir = note({ "[Log.txt](../assets/Log.txt)" }, 1, 2)
    vim.fn.mkdir(dir .. "/assets", "p")
    vim.fn.writefile({ "ERROR 4711" }, dir .. "/assets/Log.txt")
    local found = hover.target_under_cursor(0)
    local target = require("hover.classify").classify(found.target, dir .. "/Swarm/notes.md")
    assert.equals("file", target.type)
    assert.equals(
      vim.fs.normalize(dir .. "/assets/Log.txt"):lower(),
      vim.fs.normalize(target.path):lower()
    )
  end)

  it("takes a URL target, an angle-bracket target and skips a title", function()
    local buf = note({ '[Docs](https://example.com/a_(b) "The docs") [x y](<a b.md>)' }, 1, 2)
    assert.equals("https://example.com/a_(b)", md_link.under_cursor(buf).target)
    vim.api.nvim_win_set_cursor(0, { 1, 46 })
    assert.equals("a b.md", md_link.under_cursor(buf).target)
  end)

  it("takes an image, and the innermost link of a nested one", function()
    local buf = note({ "[![badge](b.svg)](https://ci.example.com)" }, 1, 4)
    assert.equals("b.svg", md_link.under_cursor(buf).target)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.equals("https://ci.example.com", md_link.under_cursor(buf).target)
  end)

  it("resolves full, collapsed and shortcut reference links through their definition", function()
    local lines = {
      "See [the log][Log Ref], [log ref][] and [Log  ref].",
      "",
      "[log ref]: ../assets/Log.txt",
    }
    for _, col in ipairs({ 6, 26, 41 }) do
      local buf = note(lines, 1, col)
      local found = md_link.under_cursor(buf)
      assert.is_not_nil(found, "col " .. col)
      assert.equals("../assets/Log.txt", found.target)
    end
    -- and the definition line itself answers with its target
    local buf = note(lines, 3, 2)
    assert.equals("../assets/Log.txt", md_link.under_cursor(buf).target)
  end)

  it("takes a bracket with no definition and no target for no link", function()
    local buf = note({ "- [x] done, see [1]" }, 1, 3)
    assert.is_nil(md_link.under_cursor(buf))
    vim.api.nvim_win_set_cursor(0, { 1, 17 })
    assert.is_nil(md_link.under_cursor(buf))
  end)

  it("ignores an escaped bracket", function()
    local buf = note({ [[\[a](b.md)]] }, 1, 2)
    assert.is_nil(md_link.under_cursor(buf))
  end)

  it("reads the bracket shape as a link only in a markdown buffer", function()
    local buf = note({ "local x = t[i](arg)" }, 1, 12, "lua")
    assert.is_nil(md_link.under_cursor(buf))
  end)

  it("stays silent with links off, and a registered source still wins", function()
    local buf = note({ "[Log.txt](a.txt)" }, 1, 2)
    hover.setup({ links = { enabled = false } })
    local found = hover.target_under_cursor(buf)
    assert.is_true(found == nil or found.kind ~= "md_link")
    hover.setup({ links = { enabled = true } })
    local registry = require("hover.registry")
    registry.register("md_link_spec", {
      sources = {
        function()
          return "from-source.md"
        end,
      },
    })
    local ok, err = pcall(function()
      assert.equals("from-source.md", hover.target_under_cursor(buf).target)
    end)
    registry.register("md_link_spec", {})
    assert(ok, err)
  end)

  it("splits a :line or :line-line suffix off a path target, and leaves a URL whole", function()
    local buf = note({ "[a](lua/hover/init.lua:50)" }, 1, 2)
    local found = md_link.under_cursor(buf)
    assert.equals("lua/hover/init.lua", found.target)
    assert.equals(50, found.line)
    assert.is_nil(found.line_end)

    buf = note({ "[a](lua/hover/init.lua:50-60)" }, 1, 2)
    found = md_link.under_cursor(buf)
    assert.equals(50, found.line)
    assert.equals(60, found.line_end)

    buf = note({ "[a](https://example.com:8080/x)" }, 1, 2)
    found = md_link.under_cursor(buf)
    assert.equals("https://example.com:8080/x", found.target)
    assert.is_nil(found.line)

    buf = note({ "[a](host:80)" }, 1, 2)
    assert.equals("host:80", md_link.under_cursor(buf).target)
  end)
end)
