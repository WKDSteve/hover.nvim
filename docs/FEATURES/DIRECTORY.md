# The directory hover: who draws the listing

A hover on a directory shows its entries as a mini filetree: a selection that
`nav_keys` move, `right` into the selected folder or open the selected file,
`left` up a level, and a left click that does both at once
([BINDINGS.md](../BINDINGS.md)). Two things can draw that listing.

| | Draws | When |
| --- | --- | --- |
| **filetree.nvim's own tree** | its `embed` layout: folders first, names without regard to case, icons with a Nerd Font, a chain of single folders `a/b/c` as one line, and a last line `… N more` for what did not fit | filetree.nvim is loaded and has the layout |
| **hover.nvim's own scan** (`hover.preview.dirbrowse`) | folders first, names in byte order, a `/` after a folder, and `… (N entries)` for what did not fit | otherwise |

The keys, the selection, the click and the window a file opens into are the
same in both: the tree is asked for lines and for what each line stands for,
and everything after that is one code path. One thing only the tree can do:
show [a folder open in place](#a-folder-open-in-place).

## Why the tree is asked and let go

The float of a hover is `focusable = false` and gone on the next cursor move.
A tree that lived in it would have to be torn down with it, on a path that an
autocmd of the float runs and this plugin does not hear about. So the tree
does not live in it: `hover.preview.dirtree` has it draw into a scratch buffer
for the length of one call, reads the lines and the rows off, closes the
handle and wipes the buffer. Nothing of the tree outlives that call: no
buffer, no watcher (`watch = false`), no autocmd and no key (the layout
creates none). `TESTS/dirtree_spec.lua` counts buffers, autocmds and handles
before and after.

The listing is flat by default: one level, as before. A line `a/b/c` stands
for the folder at its end, so `right` on it steps into `c` directly.

## A folder open in place

With filetree.nvim's tree drawing, a folder can also be shown open where it
stands, its entries indented under it. There is no key for it by default,
because a hover is gone on the next cursor move and grows under the cursor
with every folder opened; name one to have it:

```lua
require("hover").setup({
  dir_keys = { expand = { "o" } },
})
```

| Key | On a folder | On a file |
| --- | --- | --- |
| `dir_keys.expand` | open it in place, or close it again | nothing |
| `nav_keys.right`, a click | step into it: it becomes the listing | open it |

`require("hover").dir_expand()` is the same from Lua. What it changes:

- The folders that are open are remembered for as long as the float shows
  this directory. Stepping into another directory, or a new hover, starts
  flat.
- Closing a folder closes what was open inside it.
- A folder with more entries than fit gets a line `… N more` under its
  entries. That line can be selected: `right` on it steps into the folder,
  where the rest is.
- The float still shows no more entries than it has room for
  (`max_lines`); what is cut is counted on the last line.

The tree still does not live in the float. Opening a folder draws the listing
again with one folder more named as open (`hover.preview.dirtree.list(dir,
limit, expanded)`), in the same one call that asks the tree and lets it go.
So there is nothing to tear down when the float goes: the spec counts
buffers, autocmds and handles after a dismissal by cursor move, with folders
open. The key is borrowed only where the tree drew the listing: with
hover.nvim's own scan there is nothing it could do.

## Why filetree.nvim is never loaded for it

The tree is used only when filetree.nvim is already in `package.loaded`. A
`require` from here would make a plugin manager load the plugin and run its
`setup()` on the spot, for a hover over a folder name. A machine without
filetree.nvim, or with one that has no `embed` yet, never notices: the own scan
draws.

## When the tree's answer is not usable

A listing is only shown when every line stands for exactly one entry, with at
most the `… N more` line at the end. Anything else (lines and rows that do not
match, a line in the middle that is no entry, a tree that raises or has none
for this directory) hands the directory back to the own scan. A wrong line
here would not be a cosmetic defect: the line a reader selects is the file
that opens.
