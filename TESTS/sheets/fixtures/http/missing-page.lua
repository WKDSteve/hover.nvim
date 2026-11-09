-- What https://example.test/gone answers: a 404 with the server's own error page, in the shape
-- lib.nvim.net.curl.fetch_raw hands its callback. `example.test` is a reserved TLD; made up, not recorded.
return {
  status = 404,
  status_text = "Not Found",
  headers = { ["content-type"] = "text/html; charset=utf-8" },
  body = "<!doctype html><html><head><title>Page not found</title></head><body><p>Gone.</p></body></html>",
}
