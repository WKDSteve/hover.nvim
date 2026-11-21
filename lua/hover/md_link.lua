---@module 'hover.md_link'
---@brief Find the markdown link under the cursor, on its text as on its target.
---@description
--- A link is read where it is read: on its text.
---
---     Log: [Log.txt](../assets/01_2026-11-16/Log.txt)
---           └─ hover here ─┘ └──── or here ────┘
---
--- **Why this is not left to markdown.nvim.** markdown.nvim registers a link
--- scanner as a hover source (`hover.registry`), and where it is loaded it
--- answers first and this module is never asked. But hover.nvim does not need
--- markdown.nvim, and a setup without it -- a case note opened by casedesk, a
--- plain `.md` in a minimal config -- found the target part as a bare path and
--- the text as nothing at all (found 2026-11-16 by the casedesk sheet
--- `casedesk.hover-case-links`). Someone reading a link stands on its text.
---
--- **What it answers with.** The raw link target, as a registered source does:
--- `classify` resolves a relative one against the document's own directory,
--- which is what a markdown link means. The span is the whole link, text and
--- target, so the hover is the same wherever on the link the cursor rests.
---
--- **The forms.** Inline `[text](target "title")` and `[text](<a b.md>)`, the
--- image `![alt](pic.png)`, the full reference `[text][ref]`, the collapsed
--- `[ref][]` and the shortcut `[ref]` -- the last three resolved through a
--- definition `[ref]: target` anywhere in the buffer, labels compared without
--- case and with runs of whitespace folded, as CommonMark does. A shortcut
--- with no definition is no link (`[x]` is also a checkbox, an array index, a
--- citation), and a definition line itself answers with its target.
---
--- **Only in markdown buffers.** `t[i](arg)` is a call in Lua, and
--- `a[b](c)` in a good many languages; the bracket shape alone is not a link.
--- Outside a markdown filetype the target part is still found as a bare path.

local M = {}

local api = vim.api

--- Filetypes whose text is markdown. Anything containing `markdown` counts
--- too (`markdown.mdx`, `markdown.pandoc`).
---@type table<string, boolean>
local FILETYPES = {
  markdown = true,
  mdx = true,
  quarto = true,
  rmd = true,
  vimwiki = true,
  telekasten = true,
}

--- Longest line looked at. The bracket walk is linear, but a minified or
--- generated line of many kilobytes is not a document anyone reads links in.
local MAX_LINE = 4000

--- How many lines a reference definition is looked for in.
local MAX_DEF_LINES = 5000

---@param bufnr integer
---@return boolean
function M.is_markdown(bufnr)
  local ft = vim.bo[bufnr].filetype
  return FILETYPES[ft] == true or ft:find("markdown", 1, true) ~= nil
end

--- A reference label as CommonMark matches it: case folded, inner whitespace
--- runs to one space, trimmed.
---@param label string
---@return string
local function norm_label(label)
  return (label:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):lower())
end

--- Whether the byte at `i` is escaped by an odd run of backslashes before it.
---@param line string
---@param i integer
---@return boolean
local function escaped(line, i)
  local n = 0
  while i - n - 1 >= 1 and line:byte(i - n - 1) == 92 do
    n = n + 1
  end
  return n % 2 == 1
end

--- The `]` that closes the `[` at `open`, with nested brackets counted.
---@param line string
---@param open integer 1-based
---@return integer|nil
local function close_bracket(line, open)
  local depth = 0
  for i = open, #line do
    local b = line:byte(i)
    if (b == 91 or b == 93) and not escaped(line, i) then
      depth = depth + (b == 91 and 1 or -1)
      if depth == 0 then
        return i
      end
    end
  end
  return nil
end

--- The destination of an inline link whose `(` is at `open`, and the `)` that
--- ends the link. `<...>` takes everything up to `>`; otherwise the
--- destination stops at whitespace, with balanced parentheses kept (a
--- Wikipedia URL). A title after it is skipped.
---@param line string
---@param open integer 1-based, at `(`
---@return string|nil target
---@return integer|nil close 1-based, at `)`
local function inline_target(line, open)
  local i = open + 1
  while line:sub(i, i):match("^%s$") do
    i = i + 1
  end
  local target
  if line:sub(i, i) == "<" then
    local gt = line:find(">", i + 1, true)
    if not gt then
      return nil
    end
    target, i = line:sub(i + 1, gt - 1), gt + 1
  else
    local start, depth = i, 0
    while i <= #line do
      local c = line:sub(i, i)
      if c:match("%s") then
        break
      elseif c == "(" and not escaped(line, i) then
        depth = depth + 1
      elseif c == ")" and not escaped(line, i) then
        if depth == 0 then
          break
        end
        depth = depth - 1
      end
      i = i + 1
    end
    target = line:sub(start, i - 1)
  end
  -- The rest up to `)`: whitespace and at most a title in quotes or parens.
  local close = line:find(")", i, true)
  if not close then
    return nil
  end
  local rest = line:sub(i, close - 1)
  if rest:match("^%s*$") == nil and rest:match("^%s+[\"'(]") == nil then
    return nil
  end
  -- A title in parentheses holds a `)` of its own only escaped; a quoted one
  -- may hold a `)`, so step past it.
  local q = rest:match("^%s+([\"'])")
  if q then
    local endq = line:find(q, i + #rest:match("^%s+") + 1, true)
    if endq then
      close = line:find(")", endq + 1, true)
      if not close then
        return nil
      end
    end
  end
  return target, close
end

--- The target of the reference definition `[label]: target` in `bufnr`.
---@param bufnr integer
---@param label string normalized
---@return string|nil
local function definition(bufnr, label)
  if label == "" then
    return nil
  end
  local count = math.min(api.nvim_buf_line_count(bufnr), MAX_DEF_LINES)
  for _, l in ipairs(api.nvim_buf_get_lines(bufnr, 0, count, false)) do
    local lab, rest = l:match("^ ? ? ?%[([^%]]+)%]:%s*(.*)$")
    if lab and norm_label(lab) == label then
      local target = rest:match("^<([^>]*)>") or rest:match("^(%S+)")
      if target and target ~= "" then
        return target
      end
    end
  end
  return nil
end

--- Every link on `line`, with 1-based bounds of the whole link and how its
--- target is found: inline links carry it, references carry their label.
---@param line string
---@return { s: integer, e: integer, target?: string, label?: string }[]
function M.links(line)
  local out = {}
  if #line > MAX_LINE or not line:find("[", 1, true) then
    return out
  end
  local i = 1
  while true do
    local open = line:find("[", i, true)
    if not open then
      break
    end
    local close = (not escaped(line, open)) and close_bracket(line, open) or nil
    if not close then
      i = open + 1
    else
      local s = (open > 1 and line:byte(open - 1) == 33) and open - 1 or open -- `![`
      local text = line:sub(open + 1, close - 1)
      local nxt = line:sub(close + 1, close + 1)
      local link
      if nxt == "(" then
        local target, paren = inline_target(line, close + 1)
        if target then
          link = { s = s, e = paren, target = target }
        end
      elseif nxt == "[" then
        local rclose = line:find("]", close + 2, true)
        if rclose then
          local ref = line:sub(close + 2, rclose - 1)
          link = { s = s, e = rclose, label = norm_label(ref ~= "" and ref or text) }
        end
      elseif nxt == ":" and open == (line:find("%S") or 0) and open <= 4 then
        -- A definition line: it answers with its own target.
        local rest = line:sub(close + 2)
        local target = rest:match("^%s*<([^>]*)>") or rest:match("^%s*(%S+)")
        if target then
          link = { s = s, e = #line, target = target }
        end
      else
        link = { s = s, e = close, label = norm_label(text) }
      end
      if link then
        out[#out + 1] = link
      end
      -- On from the next byte either way: a link may hold another in its
      -- text (`[![badge](b.svg)](https://ci)`), and a bracket that made no
      -- link may still hold one.
      i = open + 1
    end
  end
  return out
end

--- A `:line` or `:line-line` suffix on a path target, split off the path:
--- `[x](lua/a.lua:50)` names line 50 of `lua/a.lua`, as the same text outside
--- link syntax does (bare path). A URL (`://`, a port) and a target without a
--- path shape (`host:80`) are left whole.
---@param target string
---@return string path
---@return integer|nil line
---@return integer|nil line_end
local function split_line(target)
  if target:find("://", 1, true) then
    return target
  end
  local path, first, last = target:match("^(.+):(%d+)%-(%d+)$")
  if not path then
    path, first = target:match("^(.+):(%d+)$")
  end
  if not path or not path:find("[%./\\]") then
    return target
  end
  local line, line_end = tonumber(first), tonumber(last)
  if line_end and line_end <= line then
    line_end = nil
  end
  return path, line, line_end
end

--- The link target under the cursor in a markdown buffer, in the shape
--- `hover` expects from a source.
---@param bufnr? integer
---@return Hover.Source|nil
function M.under_cursor(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= bufnr or not M.is_markdown(bufnr) then
    return nil
  end
  local pos = api.nvim_win_get_cursor(win)
  local row, col = pos[1], pos[2]
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line or not line:find("]", 1, true) then
    return nil
  end
  local c = col + 1
  -- Innermost first: `[![badge](b.svg)](https://ci)` on the badge is the badge.
  local best
  for _, link in ipairs(M.links(line)) do
    if c >= link.s and c <= link.e and (not best or link.s >= best.s) then
      best = link
    end
  end
  if not best then
    return nil
  end
  local target = best.target or definition(bufnr, best.label)
  if not target or target == "" then
    return nil
  end
  local path, line_no, line_end = split_line(target)
  return {
    target = path,
    line = line_no,
    line_end = line_end,
    lnum = row,
    col = best.s - 1,
    col_end = best.e - 1,
    kind = "md_link",
  }
end

return M
