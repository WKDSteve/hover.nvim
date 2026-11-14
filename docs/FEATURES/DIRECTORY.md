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
and everything after that is one code path.

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

The price is that the listing is flat: one level, as before. A line `a/b/c`
stands for the folder at its end, so `right` on it steps into `c` directly.

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
