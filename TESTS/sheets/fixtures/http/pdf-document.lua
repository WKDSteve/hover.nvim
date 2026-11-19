-- What https://example.test/report.pdf answers to the page fetch: a PDF by its content type, so hover downloads it
-- in a second request (preview.webpdf). Made up, not recorded; no credential. The body is not read for a PDF.
return {
  status = 200,
  status_text = "OK",
  headers = { ["content-type"] = "application/pdf", ["content-length"] = "1024" },
  body = "%PDF-1.4",
}
