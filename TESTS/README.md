# TESTS/ — what is covered, and what is not

`TESTS/` is a busted-style suite (`describe`/`it`/`before_each`/`after_each`)
run by [testing.nvim](https://github.com/WKDSteve/testing.nvim); the
project settings are in [`.testing.lua`](../.testing.lua). Every spec file
runs in a child editor of its own (`isolated = "file"`).

## Running it

```sh
bash scripts/test.sh                    # every spec
bash scripts/test.sh --file foo         # spec files whose name contains "foo"
bash scripts/test.sh --json ir.json     # also write the machine-readable result
```

`scripts/test.sh` resolves `testing.nvim` (the runner), `lib.nvim` (hard
dependency) and `ui.nvim` (needed because `TESTS/status_view_spec.lua`
asserts the dashboard actually opens) via `TESTING_NVIM_DIR`/`LIB_NVIM_DIR`/
`UI_NVIM_DIR`, a `.deps/<name>` checkout, or a sibling directory next to this
repo — see the comment at the top of `TESTS/minimal_init.lua`. `images.nvim`
is optional; without it the zoom crop spec reports `skip` (with its reason)
rather than failing. `filetree.nvim` is named there too, but only for the test
sheets `hover.http-preview-beside-explorer` and `hover.directory-expand` (and
`fileops.nvim` for `hover.fileops-on-hold`): it is
not required and not on the specs' runtimepath (a sheet adds it in its own
child); without it those sheets are a reported skip (`n/a`). CI checks it out
pinned (`ci.workflow.checkouts`).

The guards of testing.nvim are on (`guards` in `.testing.lua`): a spec that
writes outside the temp directory, starts a process other than `git`,
`magick`, `vlc` or `nvim` (the child editor of a test sheet), blocks on a
prompt or swallows a scheduled error fails.
The state guard is off (every file has its own editor).

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) is generated from
`ci.workflow` in `.testing.lua` (`testing init --workflow=public --force`) and
runs `scripts/test.sh ci` on GitHub-hosted Ubuntu (the whole profile: stylua,
luacheck, suite, conformance, surface, workflow-in-sync), Windows and macOS
(suite, conformance) on every push to `main` and every PR.

`TESTS/minimal_init.lua` sets `vim.g.lib_nvim_deps_disable_first_run`, so
no spec run opens lib.nvim's declared-tools popup — see the comment there.
A spec must not depend on which float happens to be on screen anyway, but
that popup in particular arrives on a later tick, only where a declared tool
is missing, and only in the first spec file of a run.

## Test sheets

`TESTS/sheets/*.sheet.lua` are live checks written down as data (testing.nvim's
`docs/SHEETS.md`). `TESTS/sheets_spec.lua` runs each one as the case
`sheet:<id>` in a child editor and compares its screen snapshots under
`TESTS/__snapshots__/sheets/`. `testing sheets report . --from ir.json` lists
what is left for a person (`judge` and `manual`).

| Sheet | Live-check task | Automated | Left by hand |
|---|---|---|---|
| `hover-copy-register` | `hover.nvim/copy-live-check` | `Y` and `:Hover copy` on a text hover: register text (no title), linewise, after `<C-Down>` the scrolled lines; the clipboard call is stubbed | the real system clipboard, pasting into another program, the crop of a zoomed picture / PDF page / page screenshot |
| `hover-http-preview-alone` | `hover.nvim/http-preview-live-check` | `:Hover show` on an https link: one fetch, status line, title and description (no HTML), a second hover from the session cache, a 404 | one `--live` run of `hover-http-preview-live`, the judgement of the snapshots |
| `hover-http-preview-live` | `hover.nvim/http-preview-live-check` | a **live sheet** (runs only with `testing sheets run --live`; in the suite, without `--live` and under CI a reported skip): the real curl against `https://example.com/`, the title arrives; a credential rule for `example.com/private/*` would apply over https, and the hover of the `http://` link under it hands curl no `-K`, no stdin config and no `Authorization` (every curl is recorded by a wrapper around `vim.system`) | running it once |
| `hover-http-preview-beside-explorer` | `hover.nvim/http-preview-live-check` | the same beside `:Lexplore` (filetree.nvim on netrw): the float over the note, the tree untouched, one fetch, the cache | as above |
| `hover-directory-expand` | `hover.nvim/abnahme-directory-hover-folder-open-in-place` | `:Hover show` on the path of a folder with filetree.nvim on its own tree: the flat listing, the key named for `dir_keys.expand` shows the selected folder open in place and closes it again (two snapshots), the key did not reach the buffer; a cursor move takes the float, the borrowed key, and leaves no buffer or window; so do the wheel and a click beside the float (`nvim_input_mouse`), the click landing as an ordinary click | icons with a Nerd Font, how the float grows, a real mouse |
| `hover-fileops-on-hold` | `hover.nvim/copy-live-check` | hover on CursorHold beside fileops.nvim's `on_hold` (its defaults) in a sandbox git repository, the cursor on a link in a changed, unsaved line: one float (hover's), fileops' `previous: ...` virtual text about 3 s later at the end of the line and readable on screen, neither closes the other, the next move takes both; fileops sets `'updatetime'` to 100 | a working day with both on (flicker, `'updatetime'` for other plugins), the gitsigns path of `on_hold` |
| `hover-bindings-switches` | `hover.nvim/abnahme-bindings-testblaetter` | the `:Hover` items of the nvim config's bindings checklist that set what hovers, typed with the config's setup (`_bindings.lua`): the twelve switches flip and say so, `implies`, `:Hover all`/`mode`/`auto`/`toggle`, a type switched on opens on CursorHold, `:Hover why` names the reason, `:Hover border` draws the next float, `:Hover dashboard` | what fetch/shot/office/images/positions/paths code do on real targets |
| `hover-bindings-float` | `hover.nvim/abnahme-bindings-testblaetter` | `:Hover show`, `resize` (rows), `zen` (built against the editor's height, pinned), `pin` (stays through a move, released goes), `open` (handed to `vim.ui.open`, a recorder), `next` (two position answers, wraps) | `:Hover open` through open.nvim, `:Hover next` with the config's plugins |
| `hover-bindings-effects` | `hover.nvim/abnahme-bindings-testblaetter` | what six switches do, by the trigger (`:Hover auto all`, CursorHold) and `:Hover why`: `links` (a markdown link opens its file / is no target), `links web` (an https link hovers / is no target), `links web fetch` (one request to the stub, the status line), `paths missing` (the broken-link float / named as off), `positions` (a stand-in answer / the class named as off), `paths code` (a path in Lua code named as off / opens) | a real page through `fetch` (`hover-http-preview-live`) |
| `hover-bindings-zoom` | `hover.nvim/abnahme-bindings-testblaetter` | `:Hover zoom`/`zoom in`/`out`/`reset` and `:Hover nav` on a real picture (crops written, the messages where nothing is zoomed), `:Hover images` off (the size as text) and on (the blank canvas); like `hover-copy-zoom-crop` a reported skip without images.nvim and a magick that reads a picture in the child (Windows, CI), it runs in WSL | the sharp detail in a terminal that draws pictures |
| `hover-git-object` | — | `:Hover show` on a commit id in a sandbox repository (real git, fixed dates): `git show --stat` fills the float (message, file, summary line, snapshot); a hex word that is no object says so | — |
| `hover-auth-curl` | — | a link to a host named in `links.auth` through the real lib.nvim curl transport, `curl` a recording stand-in: `-K` (the credential on stdin), the token nowhere on the command line; a link to another host without `-K` | a real host behind a credential |
| `hover-web-pdf-download` | — | a link whose page fetch (stub) answers `application/pdf`: one `curl -o` download (stand-in) with `--globoff` and the PDF Accept header; the stand-in writes nothing and the hover says the document did not download | a real PDF's first page (pdftoppm, an image provider) |
| `hover-shot-browser` | — | `:Hover show` on a link with `links.shot` on and `links.shot.command` named: the browser (stand-in `chromium`) gets `--headless=new`, a `--screenshot` file in hover's cache and the link; it draws nothing and the hover says the page did not render | the lookup of an installed Chrome, a real picture |
| `hover-focus-mouse` | `hover.nvim/hover-focus-maus-handpruefung-auswahl-rad-q-esc` | `:Hover focus` on a text hover, then through `nvim_input_mouse`: a drag selects words (Visual mode, snapshot) and `y` yanks exactly them; the wheel scrolls the float, not the window behind; `q` and `<Esc>` lead back to the origin window, the float stays up and the next cursor move closes it | a real mouse (a picture hover refusing to be entered is `focus_spec.lua`) |

The network in a sheet is a stub (`_G.net_stub` in `TESTS/sheets/_helpers.lua`
replaces `lib.nvim.net.curl`): nothing is spawned or connected, the process
guard stays strict, `curl` is not in `guard_allow`. The answers are data in
`TESTS/sheets/fixtures/http/` (hosts under the reserved `example.test`). The
exception is the live sheet `hover-http-preview-live`: it reaches
`example.com` and nothing else (`live.hosts`), and never in the suite or on CI.
A program hover starts itself (curl for a download or an authenticated fetch,
the browser of a page shot) is a recording stand-in (`fakes`) where its effect
would leave the editor; the sheet reads its command line. git runs for real.
These sheets exist so that `testing perf` reaches every process start of
hover (`TESTS/sheets/features.lua` says, per functionality, which sheet that is
or why there is none).

## Coverage map

One row per module under `lua/hover/**` (`@types`/`---@meta` files excluded
— see below). "Dedicated spec" means a spec file whose own `describe` block
is about that module specifically, as opposed to the module merely being
`require()`d as a supporting dependency by a spec about something else.

| Module | Spec | Notes |
| --- | --- | --- |
| `bare_git.lua` | `bare_git_spec.lua` | |
| `bare_path.lua` | `bare_path_spec.lua` | |
| `bare_url.lua` | `bare_url_spec.lua` | added by the 2026-09-18 audit (see below) |
| `bindings/autocmds.lua` | `registry_spec.lua` | `attach`/`anything_to_show`/`detach_all` all directly exercised, including that a wiped buffer and `detach_all` take back the records and the group (`taking it back`) |
| `bindings/init.lua` | — | three-line aggregator, no branching of its own; each of the three `setup()`s it calls is covered where it is used directly |
| `bindings/keymaps.lua` | `playback_spec.lua`, `resize_spec.lua`, `zen_spec.lua`, `zoom_spec.lua`, `office`/`shot` via others | borrow/release behaviour asserted directly in each |
| `bindings/usrcmds.lua` | `docs_spec.lua`, `resize_spec.lua`, `switches_spec.lua`, `usrcmds_help_spec.lua`, `zen_spec.lua`, `zoom_spec.lua` | route table cross-checked against `docs/commands.md` in `docs_spec.lua`; every positional argument has a one-line text for lib.nvim's option float in `usrcmds_help_spec.lua` |
| `cache.lua` | `shot_spec.lua`, `switches_spec.lua`, `url_spec.lua`, `webpdf_spec.lua` | |
| `classify.lua` | `classify_spec.lua` | added by the 2026-09-18 audit — previously reached only incidentally, with an already-existing path handed to it |
| `config/auto_types.lua` | `switches_spec.lua` | one function, one branch (append `"position"`, sort); exercised as a dependency |
| `config/DEFAULTS.lua` | — | data only, see below |
| `config/init.lua` | `config_spec.lua` | |
| `copy.lua` | `copy_spec.lua` | the clipboard stubbed (lib.nvim's `copy_to_clipboard` may start a process the guards refuse); the text path through a real float, the picture path through `take` |
| `init.lua` (`ocr`) | `ocr_spec.lua` | `:Hover ocr` / `gO` on a real float: the answers that never reach images.nvim (no hover, no picture) and the key borrow; the OCR itself is images.nvim's |
| `float.lua` | `registry_spec.lua`, `resize_spec.lua`, `zen_spec.lua`, `zoom_spec.lua`, `video_spec.lua` | the most heavily exercised module in the suite; every sizing/positioning path is driven through a real float |
| `formats.lua` | `video_spec.lua` | data table + three lookups; no dedicated file needed |
| `health.lua` | `health_spec.lua` | added by the 2026-09-18 audit — had zero coverage before it; see below |
| `init.lua` | nearly every spec | `require("hover")` is the plugin's own public surface; exercised end to end throughout |
| `linkcache.lua` | `linkcache_spec.lua` | driven through `preview.url.fetch` with `lib.nvim.net.curl` stubbed; "a new session" is the in-memory stores dropped with the directory left standing |
| `notify.lua` | — | a one-line re-export of `lib.nvim.notify`; nothing of its own to test |
| `persist.lua` | `persist_spec.lua` | |
| `preview/align_win.lua` | — | excluded, see below |
| `preview/binary.lua` | `binary_spec.lua` | added by the 2026-09-18 audit |
| `preview/external.lua` | `external_spec.lua` | |
| `preview/git.lua` | `git_spec.lua` | added by the 2026-09-18 audit |
| `preview/media.lua` | `resize_spec.lua`, `zoom_spec.lua`, `window_spec.lua`, `office_spec.lua` (stubbed) | |
| `preview/monitor.lua` | `monitor_spec.lua` | added by the 2026-09-18 audit; the OS scripts themselves are excluded, see below |
| `preview/office.lua` | `office_spec.lua` | added by the 2026-09-18 audit — the module exported `M.reset()` with a doc comment saying it exists for tests, and had none |
| `preview/playback.lua` | `playback_spec.lua` | |
| `preview/shot.lua` | `shot_spec.lua` | |
| `preview/text.lua` | `bare_path_spec.lua`, `registry_spec.lua` | |
| `preview/url.lua` | `url_spec.lua` | |
| `preview/video.lua` | `video_spec.lua` | |
| `preview/webpdf.lua` | `webpdf_spec.lua` | |
| `preview/window.lua` | `window_spec.lua` | |
| `registry.lua` | `registry_spec.lua` | |
| `scope.lua` | `scope_spec.lua` | |
| `status_view.lua` | `status_view_spec.lua` | |
| `switches.lua` | `switches_spec.lua` | |

## Deliberately not covered, and why

- **`@types/init.lua` (top-level, `bindings/`, `config/`, `preview/`)** —
  LuaLS annotations only, no runtime code.
- **`config/DEFAULTS.lua`** — data only by its own doc comment ("Nothing
  here reads the editor, calls an API, or depends on another module"); every
  value in it is exercised indirectly by whichever spec depends on that
  default, and `switches_spec.lua`/`docs_spec.lua` already cross-check its
  shape against `classify.TYPES` and the vimdoc.
- **`notify.lua`** — a one-line re-export; the implementation it forwards to
  is `lib.nvim.notify`'s to test.
- **`preview/align_win.lua`** — `M.try_centre_new_window()` writes a
  disposable PowerShell/AppleScript/bash script to `stdpath("cache")` and
  runs it to move a *real OS window* it does not control. Its own module doc
  states the contract outright: "never blocks, never raises, never reports
  back" — there is no return value, no callback and no observable effect
  from Lua once the process is launched, only whatever actually happens on
  screen. `TESTS/external_spec.lua` already asserts that this function gets
  *called* at the right moment (`"still asks align_win to centre the window
  after a known player launch"`); asserting anything about the generated
  script text itself would be testing embedded PowerShell with Lua string
  assertions, not testing behaviour.
- **`preview/monitor.lua`'s OS scripts** — `script_windows`/`script_macos`/
  `script_linux` generate the PowerShell/AppleScript/bash bodies that query a
  real window manager; `TESTS/monitor_spec.lua` covers everything else in
  this module (`M.detect`'s stdout-parsing branches, via a stubbed
  `vim.system`) but not the script bodies themselves — the CI workflow
  documents this whole family as "evidenced only by hand," and that stance
  is unchanged by this audit.
- **Real external processes in general** — `pdftoppm`/`ffmpeg`/`soffice`/
  `mpv` actually rasterizing, transcoding or playing something, and real
  network requests, are exercised nowhere in this suite; `webpdf_spec.lua`
  and `office_spec.lua` both test everything *around* those calls (caching,
  eviction, refusal, error shaping) with the call itself stubbed.
- **UI that needs a real live backend** — `images.nvim` actually drawing a
  picture, and the ImageMagick-backed zoom crop check, report `skip` with
  their reason in CI rather than being skipped silently; a skip is its own
  status in the runner's summary and never counts as a pass
  (`zoom_spec.lua`'s crop check once went unnoticed for a period because a
  `pending()` inside an `it()` still counted as a `Success` in the old
  runner's summary).

## The 2026-09-18 audit

This repository had never had a full audit round in the cross-repo
test-coverage campaign — it was spot-checked once via a file-count proxy (40
`lua` files vs. 38 spec files) and marked "already looks good" on that ratio
alone. This was the first real one.

**What it found:** the existing 19 spec files (474 assertions) were all
real, assertion-based specs — no smoke-test-only files, no padding. Six
modules had never been reached by a dedicated spec at all:
`hover.classify`, `hover.bare_url`, `hover.health`, `hover.preview.binary`,
`hover.preview.git` and `hover.preview.office`; a seventh,
`hover.preview.monitor`, had its own result-parsing logic untested even
though the module existed. All seven now have one (`classify_spec.lua`,
`bare_url_spec.lua`, `health_spec.lua`, `binary_spec.lua`, `git_spec.lua`,
`office_spec.lua`, `monitor_spec.lua` — 98 new assertions).

**No behavioural bug was found or needed fixing.** The audit paid specific
attention to four patterns a related campaign has repeatedly found across
nearly thirty other repositories, and checked each one against this code
rather than assuming it clean:

1. A `health.lua` whose "dependency is missing" branch calls on into the
   missing dependency anyway. `hover/health.lua`'s own doc comment already
   names this exact failure mode ("Checks truth, not presence") and its
   `check_lib()`/`soft()` helpers already guard against it correctly —
   `health_spec.lua`'s first two tests exercise the missing-hard-dependency
   and missing-optional-dependency paths with `M.check()` itself wrapped in
   `pcall`, and both confirm it degrades to a warning/error rather than
   raising.
2. An augroup created without clearing on a second `setup()`.
   `bindings/autocmds.lua`'s `M.enable()`/`M.attach()` already clear their
   groups (`autocmd.group(name, true)`) and `registry_spec.lua` already
   exercises `detach_all()`/re-`attach()` directly; nothing new was found.
3. Byte-offset vs. display-column confusion in cursor-position logic. Every
   position-comparison path in this plugin (`bare_path.lua`, `bare_url.lua`,
   `init.lua`'s `target_under_cursor`/`show_position`) consistently uses the
   byte-based column `nvim_win_get_cursor` returns, with no
   `strdisplaywidth`/`charidx` mixed in anywhere along that path.
   `bare_url_spec.lua` pins this explicitly for the module doing the most
   arithmetic on it — spans reported in the same 0-based byte units the
   cursor API uses, asserted at both the start and the inclusive end of a
   span.
4. Windows path/drive-letter bugs. `classify.lua` already guards the exact
   collision (`C:\Users\...` read as a two-character-minimum URL scheme)
   with `raw:match("^%a[%w+.-]*:") and not raw:match("^%a:[\\/]")`, and
   `bare_url.lua` requires the same two-character minimum independently.
   Both guards are now pinned by a dedicated test
   (`classify_spec.lua`/`bare_url_spec.lua`) rather than only readable by
   inspection, and both were verified empirically on this Windows machine,
   not merely by reading the pattern.

**Before/after:** 19 → 26 spec files, 474 → 572 assertions, 0 failures/
errors/pending in both counts, confirmed stable across two consecutive runs
before and after. `stylua --check` and `luacheck lua plugin` — the exact
commands `.github/workflows/ci.yml` runs — are clean.
