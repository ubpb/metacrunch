# Changelog

## 5.0.0 (unreleased)

The first version, for metacrunch 5. It replaces the XLSX sink of the 4.x gem metacrunch-file, which was built on
caxlsx.

### Added

- `Metacrunch::Xlsx::Writer`, a sink on `Metacrunch::Output` that streams one worksheet: `columns:` (an Array of keys
  or a Hash of header name => key) or the keys of the first record, `header:`, `sheet:` and `widths:`. The header row
  is bold, frozen and filtered. Cells follow the Ruby type of their values. Excel's limits are errors with the
  record's position. The file is finished also when a run aborts.

### Changes from metacrunch-file

- Cells are no longer all text: Integers and Floats are numbers, `true` and `false` booleans.
- One record is one row; the writer streams instead of keeping the workbook in memory (100,000 rows × 10 cells: about
  40 MB instead of about 300 MB).
