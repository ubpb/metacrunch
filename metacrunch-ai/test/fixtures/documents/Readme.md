# Documents for the Tika tests

Made once with pandoc, LibreOffice and qpdf:

- `handbook.docx`: `pandoc handbook.md -o handbook.docx` from a Markdown file with the headings "Borrowing" (level 1)
  and "Renewals" (level 2).
- `loans.pdf`, two pages, titled "Loans and renewals": `pandoc loans.md -o loans.docx` from a Markdown file with that
  `title` in its front matter and a raw OpenXML page break (`<w:p><w:r><w:br w:type="page"/></w:r></w:p>`), then
  `soffice --headless --convert-to pdf loans.docx`.
- `encrypted.pdf`: `qpdf --encrypt user owner 256 -- loans.pdf encrypted.pdf`.
- `truncated.pdf`: `head -c 300 loans.pdf > truncated.pdf`.
