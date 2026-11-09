-- What https://example.test/page answers: the shape lib.nvim.net.curl.fetch_raw hands its callback.
-- `example.test` is a reserved TLD: this can never be a real host. Made up, not recorded; no credential.
return {
  status = 200,
  status_text = "OK",
  headers = { ["content-type"] = "text/html; charset=utf-8" },
  body = table.concat({
    "<!doctype html><html><head><title>Example Domain</title>",
    '<meta name="description" content="A page for the test sheets of hover.nvim.">',
    "</head><body><h1>Example Domain</h1><p>Hello.</p></body></html>",
  }),
}
