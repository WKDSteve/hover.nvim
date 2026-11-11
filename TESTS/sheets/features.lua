-- TESTS/sheets/features.lua -- the functionalities of hover.nvim as its reader meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names
-- an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The why of each one is in docs/FEATURES/; the list follows docs/FEATURES/README.md.
return {
  {
    id = "hover.http-preview",
    title = "A hover over an http(s) link shows the status, the title and the description of the page",
    surface = { "command:Hover show", "config:links.web", "config:links.fetch" },
    docs = "docs/configuration.md",
  },
  {
    id = "hover.copy",
    title = "Y or :Hover copy puts what the hover shows into the register and the clipboard",
    surface = { "command:Hover copy", "binding:Y" },
    docs = "docs/FEATURES/COPY.md",
  },
  {
    id = "hover.quiet",
    title = "Little is on by default: a hover opens only where it has something to say",
    docs = "docs/FEATURES/QUIET.md",
  },
  {
    id = "hover.bare-paths",
    title = "A path without link syntax around it previews the file it names",
    docs = "docs/FEATURES/BARE-PATHS.md",
  },
  {
    id = "hover.contributions",
    title = "Another plugin or the config adds a preview of its own",
    docs = "docs/FEATURES/CONTRIBUTIONS.md",
  },
  {
    id = "hover.resize",
    title = "+ and - (and the wheel) make the hover bigger and smaller",
    docs = "docs/FEATURES/RESIZE.md",
  },
  {
    id = "hover.web-pdf",
    title = "A link that answers with a PDF shows its first page",
    docs = "docs/FEATURES/WEBPDF.md",
  },
  {
    id = "hover.shot",
    title = "A hovered link shows a picture of the page",
    docs = "docs/FEATURES/SHOT.md",
  },
  {
    id = "hover.pins",
    title = "A link pinned to a file of your own shows that file",
    docs = "docs/FEATURES/PINS.md",
  },
  {
    id = "hover.link-cache",
    title = "A fetched page of the links you name is kept across sessions",
    docs = "docs/FEATURES/LINKCACHE.md",
  },
  {
    id = "hover.auth",
    title = "A link to a host you named is fetched with its credential, and no other one",
    docs = "docs/FEATURES/AUTH.md",
  },
  {
    id = "hover.zen",
    title = "Zen shows the hover on the whole editor, with the screen as its budget",
    docs = "docs/FEATURES/ZEN.md",
  },
  {
    id = "hover.zoom",
    title = "A picture or a page in the hover zooms (not resize: the content, not the window)",
    docs = "docs/FEATURES/ZOOM.md",
  },
  {
    id = "hover.video",
    title = "A video file under the cursor shows a still from it, and the paging keys step through it",
    docs = "docs/FEATURES/VIDEO.md",
  },
}
