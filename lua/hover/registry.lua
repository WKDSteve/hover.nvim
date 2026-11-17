---@module 'hover.registry'
--- Sources and previews a plugin contributes to the hover.
---@description
--- **The problem.** The hover framework knows how to find a path under the
--- cursor, classify it and draw a float around whatever comes back. It must
--- not know *who* can read a `#heading` out of a markdown file, or who can
--- turn a `.png` into pixels. Those are plugin capabilities, and a library
--- that requires plugins to do its job has the dependency backwards: install
--- lib.nvim on its own and half of it would be missing.
---
--- **The shape.** Plugins register into the library rather than the library
--- reaching for plugins. Two kinds of contribution, because the hover asks
--- two separate questions:
---
--- ```lua
--- hover.register("markdown", {
---   -- "what is under the cursor?" -- returns a raw target string, or nil.
---   -- Tried in registration order, before the built-in bare-path source.
---   sources = {
---     function(bufnr, row, col) return link_scan_at(bufnr, row, col) end,
---   },
---   -- "how do I preview a target of this type?" -- keyed by the type
---   -- `classify` produced. Asked before the built-in preview for that
---   -- type; returning nil hands the target on (see "chain" below).
---   previews = {
---     anchor = function(target, opts, bufnr) return section_of(target, bufnr) end,
---   },
--- })
--- ```
---
--- **Why both are ordered.** Several sources can match the same cursor
--- position -- a markdown link and a bare path both exist on `[a](./b.png)`
--- -- so "first match wins" needs an order, and registration order is the
--- only one a library can honestly offer.
---
--- Previews were once one per type, a second registration replacing the
--- first. That held until two plugins wanted the same type for different
--- files: testing.nvim previews its spec files, casedesk.nvim the logs of a
--- case, and both register `file`. Whichever loaded last silently took the
--- other's preview away. So the previews of one type form a **chain**: asked
--- in order, each may decline (`nil`) and hand the target to the next, and
--- the built-in preview answers when every one declined. The order is
--- registration order, unless an entry states a `priority` (higher first,
--- default 0) -- the one way to go ahead of a plugin that registered earlier,
--- which is what an override in a user's own config needs.
---
--- **Why a plugin name is required.** Re-registering under the same name
--- replaces that plugin's contribution instead of stacking a second copy on
--- top: `setup()` running twice (a reload, a `:Lazy reload`) must not make
--- every source fire twice.

local M = {}

-- `Hover.Contribution`, `Hover.SourceFn` and `Hover.PreviewFn` are declared in
-- `hover.@types`. Re-declaring them here duplicated every field: an alias name
-- is global to LuaLS, and reopening a class to restate a field is a
-- `duplicate-doc-field`, not an override (`LLS-23`).

---@type { name: string, fn: function, on_request: boolean }[]
local sources = {}

---@type table<string, { name: string, fn: function, priority: number, seq: integer }[]>
local previews = {}

--- Registration counter: the tie-break between previews of equal priority.
--- A plugin registering again keeps the number it had, so a retry or a second
--- `setup()` does not move it behind a plugin that registered in between.
local seq = 0

---@type { name: string, fn: function, on_request: boolean }[]
local positions = {}

---@internal
--- Read one entry of a `sources` or `positions` list.
---
--- **Two shapes, and the second is why.** A bare function is asked on every
--- trigger, which is right for a contribution that is cheap and quiet. A
--- table entry can say `on_request = true`, and then it is asked only for an
--- explicit request -- `:Hover show`, or a key bound to it.
---
--- That flag exists because "how expensive is your answer" is knowledge only
--- the contributor has, and there was no way to state it. Measured, the
--- population that needs it: a git start costs ~41 ms, a `docker --version`
--- 230 ms, `podman --version` 490 ms -- the same whether they hit or miss.
--- A trigger that fires after every keystroke followed by quiet cannot pay
--- that, and the alternative on offer was `:Hover positions off`, which
--- silences every registered plugin at once rather than the expensive one.
---
--- The flag lives on the *entry* rather than in a fourth contribution kind
--- because it applies to both existing kinds identically. A
--- `sources_on_request` list would have needed a `positions_on_request`
--- beside it, and the pair would then have to stay in step by hand -- this
--- repository has been bitten three times by exactly that shape.
---@param entry any
---@return function|nil fn
---@return boolean on_request
local function normalize(entry)
  if type(entry) == "function" then
    return entry, false
  end
  if type(entry) == "table" and type(entry.fn) == "function" then
    return entry.fn, entry.on_request == true
  end
  return nil, false
end

---@internal
--- Read one value of a `previews` table: a bare function (priority 0), or
--- `{ fn = ..., priority = n }`.
---@param value any
---@return function|nil fn
---@return number priority
local function normalize_preview(value)
  if type(value) == "function" then
    return value, 0
  end
  if type(value) == "table" and type(value.fn) == "function" then
    return value.fn, type(value.priority) == "number" and value.priority or 0
  end
  return nil, 0
end

--- Register a plugin's hover contributions.
---@param name string plugin name; re-registering replaces its previous entry
---@param contribution Hover.Contribution
---@return nil
function M.register(name, contribution)
  if type(name) ~= "string" or name == "" then
    return
  end
  contribution = contribution or {}

  -- Drop this plugin's previous sources before adding the new ones, so a
  -- second setup() replaces rather than duplicates.
  local kept = {}
  for _, entry in ipairs(sources) do
    if entry.name ~= name then
      kept[#kept + 1] = entry
    end
  end
  sources = kept

  local kept_positions = {}
  for _, entry in ipairs(positions) do
    if entry.name ~= name then
      kept_positions[#kept_positions + 1] = entry
    end
  end
  positions = kept_positions

  for _, entry in ipairs(contribution.sources or {}) do
    local fn, on_request = normalize(entry)
    if fn then
      sources[#sources + 1] = { name = name, fn = fn, on_request = on_request }
    end
  end

  -- Drop this plugin's previews of every type, remembering where each stood:
  -- a type it no longer names is gone, one it names again keeps its place.
  ---@type table<string, integer>
  local had = {}
  for target_type, chain in pairs(previews) do
    local kept_chain = {}
    for _, entry in ipairs(chain) do
      if entry.name == name then
        had[target_type] = entry.seq
      else
        kept_chain[#kept_chain + 1] = entry
      end
    end
    previews[target_type] = #kept_chain > 0 and kept_chain or nil
  end

  for target_type, value in pairs(contribution.previews or {}) do
    local fn, priority = normalize_preview(value)
    if type(target_type) == "string" and fn then
      local chain = previews[target_type] or {}
      local at = had[target_type]
      if not at then
        seq = seq + 1
        at = seq
      end
      chain[#chain + 1] = { name = name, fn = fn, priority = priority, seq = at }
      table.sort(chain, function(a, b)
        if a.priority ~= b.priority then
          return a.priority > b.priority
        end
        return a.seq < b.seq
      end)
      previews[target_type] = chain
    end
  end

  for _, entry in ipairs(contribution.positions or {}) do
    local fn, on_request = normalize(entry)
    if fn then
      positions[#positions + 1] = { name = name, fn = fn, on_request = on_request }
    end
  end
end

--- Ask every registered source, in registration order, for the target under
--- the cursor. The first one that answers wins.
---@param bufnr integer
---@param row integer 1-based
---@param col integer 0-based
---@return string|nil target
---@return table|nil extra fields the source wants carried on the record
function M.source_at(bufnr, row, col, opts)
  local force = type(opts) == "table" and opts.force == true
  for _, entry in ipairs(sources) do
    -- An `on_request` source is skipped on the automatic trigger: its author
    -- said its answer is expensive, and only they could know.
    if force or not entry.on_request then
      -- `pcall`: a broken contribution from one plugin must not take the
      -- hover down for every other.
      local ok, target, extra = pcall(entry.fn, bufnr, row, col)
      if ok and type(target) == "string" and target ~= "" then
        return target, extra
      end
    end
  end
  return nil
end

--- Ask the previews registered for `target.type`, in chain order. The first
--- one that answers wins; one that declines (`nil`, or an error) hands the
--- target to the next.
---
--- `pcall` per entry, for the reason `source_at` gives: one broken preview
--- must not take the others in the chain down with it.
---@param target Hover.Target
---@param opts Hover.PreviewOpts
---@param bufnr integer
---@return Hover.Content|nil content
---@return string|nil name the plugin that answered
function M.preview(target, opts, bufnr)
  local chain = type(target) == "table" and previews[target.type]
  if not chain then
    return nil
  end
  -- A copy: a preview that registers (or re-registers) while being asked
  -- must not reorder the list under this loop.
  for _, entry in ipairs(vim.list_slice(chain)) do
    local ok, content = pcall(entry.fn, target, opts, bufnr)
    if ok and content then
      return content, entry.name
    end
  end
  return nil
end

--- The registered preview for `target_type`, if a plugin claimed it.
---
--- Kept for callers from before previews were chained. With one preview
--- registered it is that function itself; with several, one function that
--- asks the chain as it stands **now** -- a snapshot, so a plugin that
--- captures it to wrap and then registers its own wrapper for the same type
--- does not end up asking itself. New code calls `preview` instead.
---@param target_type string
---@return function|nil
function M.preview_for(target_type)
  local chain = previews[target_type]
  if not chain then
    return nil
  end
  if #chain == 1 then
    return chain[1].fn
  end
  local snapshot = vim.list_slice(chain)
  return function(target, opts, bufnr)
    for _, entry in ipairs(snapshot) do
      local ok, content = pcall(entry.fn, target, opts, bufnr)
      if ok and content then
        return content
      end
    end
    return nil
  end
end

--- The plugins that registered a preview for `target_type`, in the order
--- they are asked. For `:checkhealth` and tests: names, not the functions,
--- for the reason `contributors` gives.
---@param target_type string
---@return string[]
function M.preview_names(target_type)
  local out = {}
  for _, entry in ipairs(previews[target_type] or {}) do
    out[#out + 1] = entry.name
  end
  return out
end

--- Ask every registered *position* preview, in registration order, for
--- something to say about this cursor position. The first one that answers
--- wins.
---
--- Asked only after every source has declined, because a target is the more
--- specific reading of the same place: on `./docs/x.md` inside a deprecated
--- call, the file is what the reader pointed at.
---
--- Unlike a source this returns finished content rather than a string to
--- classify -- there is nothing to classify, which is the entire point of the
--- kind. See `Hover.PositionFn`.
---
--- **`opts.nth` steps past the winner.** Several plugins can have something to
--- say about one place, and they often do: a dotted name is both "what is this
--- module" (docmap.nvim) and "who imports it" (insights.nvim). First
--- match wins is right for a *source*, where the answers compete to describe
--- the same target -- and wrong here, where they are different sentences about
--- the same place, and the loser is invisible rather than outranked. Which one
--- won was decided by nothing better than plugin load order.
---
--- So the caller can ask for the second answer, the third, and so on;
--- `hover.next_position` walks them. Answers are counted, not contributors:
--- a plugin that declines here is not a page the reader has to step past.
---
--- **Nothing is asked eagerly.** There is deliberately no "how many answers
--- are there" -- finding out would mean calling every contribution on every
--- trigger, which is exactly the cost `on_request` exists to avoid. The reader
--- discovers a second answer by asking for it.
---@param bufnr integer
---@param row integer 1-based
---@param col integer 0-based
---@param opts? { force?: boolean, nth?: integer } `nth` is 1-based, over the contributions that *answer*
---@return Hover.Content|nil content
---@return string|nil name the plugin that answered, for the dismissal identity
function M.position_at(bufnr, row, col, opts)
  local force = type(opts) == "table" and opts.force == true
  local want = math.max(1, math.floor((type(opts) == "table" and opts.nth) or 1))
  local seen = 0
  for _, entry in ipairs(positions) do
    if force or not entry.on_request then
      -- `pcall` for the same reason as `source_at`: one broken contribution
      -- must not take the hover down for every other.
      local ok, content = pcall(entry.fn, bufnr, row, col)
      if
        ok
        and type(content) == "table"
        and type(content.lines) == "table"
        and #content.lines > 0
      then
        seen = seen + 1
        if seen == want then
          return content, entry.name
        end
      end
    end
  end
  return nil
end

--- Whether any source is registered. `markdown.hover`'s link scanning is the
--- usual one; without it the hover still works from bare paths alone.
---@return boolean
function M.has_sources()
  for _, entry in ipairs(sources) do
    if not entry.on_request then
      return true
    end
  end
  return false
end

--- Whether any position preview is registered. Separate from `has_sources`
--- because the two answer different questions: the trigger needs to know
--- whether *anything* could answer, and a buffer with only a position
--- preview registered is still a buffer worth waking for.
---@return boolean
function M.has_positions()
  for _, entry in ipairs(positions) do
    if not entry.on_request then
      return true
    end
  end
  return false
end

--- Every registered contributor, with how much each of them registered.
---
--- Exists for `:checkhealth`, and for one question in particular. Since
--- `c374d5e` a hover can be written in a user's own config, and the first
--- thing anyone asks after handing a function to `setup({ contribute = ... })`
--- is "is it registered at all?". Nothing here could answer that.
--- `has_sources()` looks as though it does and does not: it reports whether
--- *anybody* registered a link source, so it says "no" to a config whose
--- contribution is a position preview, and "yes" -- about markdown.nvim -- to
--- one whose contribution silently failed.
---
--- **Counts, not the functions.** What the question needs is arrival and
--- volume. Handing back the callables would make an accessor into a second
--- way to run them, from outside the `pcall` that keeps one broken
--- contribution from taking the hover down for every other.
---
--- **Sorted by name**, because one of the three lists read here is keyed by
--- target type rather than ordered, and `pairs` order is not stable. A health
--- report that shuffles between two runs on the same configuration cannot be
--- compared against itself, which is most of what a health report is for.
---@return Hover.Contributor[]
function M.contributors()
  ---@type table<string, Hover.Contributor>
  local seen = {}

  ---@param name string
  ---@return Hover.Contributor
  local function entry_for(name)
    if not seen[name] then
      seen[name] = { name = name, sources = 0, previews = 0, positions = 0, on_request = 0 }
    end
    return seen[name]
  end

  for _, entry in ipairs(sources) do
    local contributor = entry_for(entry.name)
    contributor.sources = contributor.sources + 1
    if entry.on_request then
      contributor.on_request = contributor.on_request + 1
    end
  end

  for _, chain in pairs(previews) do
    for _, entry in ipairs(chain) do
      local contributor = entry_for(entry.name)
      contributor.previews = contributor.previews + 1
    end
  end

  for _, entry in ipairs(positions) do
    local contributor = entry_for(entry.name)
    contributor.positions = contributor.positions + 1
    if entry.on_request then
      contributor.on_request = contributor.on_request + 1
    end
  end

  local out = {}
  for _, contributor in pairs(seen) do
    out[#out + 1] = contributor
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- How many position contributions are registered.
---
--- Registered, **not** answering: finding out how many would answer means
--- asking all of them, and this is read on every hover that opens. It exists
--- for one decision -- whether to borrow a key for stepping between answers --
--- and for that "could there be a second one at all" is the honest question.
--- A key bound where nothing further answers costs one press and a message; a
--- contribution called on every trigger costs what `on_request` was built to
--- stop.
---@return integer
function M.position_count()
  return #positions
end

--- Drop every registration. Tests only.
---@return nil
function M.reset()
  sources, previews, positions = {}, {}, {}
  seq = 0
end

return M
