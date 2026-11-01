# 4. Read XLSX without a spreadsheet or XML library

- Status: accepted
- Date: 2026-11-01

## Context

metacrunch-xlsx wrote workbooks but read none. Much tabular data is kept and delivered as Excel files: lists,
exports, the tables of statistics offices and data portals. Without a reader, every such job converts the workbook to
CSV first. The core reads ZIP archives itself (ADR 0002), so a workbook's parts are at hand. What is left is the XML of
the parts and the rules of the format: shared strings, number formats that make a number a date, two date systems,
and Excel's codes for characters (`_x000D_`).

Measured on 100,000 rows of 10 cells:

| | Time | Peak memory |
|---|---|---|
| roo, streaming (Nokogiri, rubyzip) | 5.5 s | 154 MB |
| Nokogiri::XML::Reader, parsing only, no values converted | 1.3 s | |
| a scanner of our own with all conversion, as released | 2.5 s | 51 MB |

roo and Nokogiri were measured on the workbook of a first prototype, the released reader on the workbook of
`bench/reader.rb` (shared strings, styles, dates): the rows compare orders of magnitude, not exact times.

## Decision

The reader is pure Ruby. It opens a workbook with `Metacrunch::Input::Zip` (through `Input#each_zip`) and reads a sheet
with a scanner of its own, one `<row>` at a time from the inflated part. There is no XML library, no spreadsheet
library and no new dependency. The scanner resolves only the five predefined entities and character references and
refuses a DOCTYPE. Values come as the cells store them, and dates as ISO 8601 Strings, so that every sink takes them.
Header rules and record shapes are those of the CSV reader.

## Alternatives

- roo: two to three times the time and memory, with Nokogiri and rubyzip as dependencies. It gives HTML for rich text
  and leaves Excel's character codes in the text, and its values follow its own rules (`Date`, `DateTime`).
- creek: streams with Nokogiri, has not been maintained for years, and leaves the same conversion to do.
- Nokogiri directly: a native dependency for one gem. It parses faster, but shared strings, formats, dates and
  character codes would still be our code, and its parser would have to be kept from resolving entities.
- zip_kit to read the archive: it checks no CRCs (see ADR 0002).

## Consequences

- About 800 lines to maintain: reader, scanner, number formats, dates and the workbook's parts. They are guarded by
  unit tests for each rule, a fuzz test over mutated parts, and a one-off check against openpyxl. That check covered
  36 workbooks from seven writers, Excel files of statistics offices among them, with 771,635 cells. The only
  differences left were Excel's character codes, which the reader decodes as Excel does, and date numbers below 1.
- The rules of the format are ours to know. A new writer or Excel version may need a change, and a check against
  other readers is the way to find it.
- Formulas are not computed and formats are not applied: the reader gives what the cells store.
- A workbook's shared strings are held in memory while its sheet is read.
