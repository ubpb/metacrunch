# Changelog

## 5.0.0 (unreleased)

The first version, for metacrunch 5. It replaces the CSV source and sink of the 4.x gem metacrunch-file, which were
built on smarter_csv.

### Added

- `Metacrunch::Csv::Reader`, a source on `Metacrunch::Input` and Ruby's `csv`: files, stdin, IOs, gzip and tar; the
  options `col_sep:`, `quote_char:`, `encoding:` and `headers:`; Hash records with String keys and String values,
  `""` for empty and `nil` for missing fields; the byte order mark is removed and values are UTF-8; a row that cannot
  be read becomes a `Metacrunch::InvalidRecord`.
- `Metacrunch::Csv::Writer`, a sink on `Metacrunch::Output`: `columns:` (an Array of keys or a Hash of header name =>
  key) or the keys of the first record, `header:`, `col_sep:`, `quote_char:`, `encoding:` and `bom:`. Strings,
  Integers, Floats, BigDecimals, `true`, `false` and `nil` are written; other values stop the run.

### Changes from metacrunch-file

- Values stay Strings: `"00123"` is no longer read as `123`. Keys are the column names as Strings, not downcased
  Symbols. Empty fields are `""` instead of being left out.
- The options are the gem's own, not those of smarter_csv.
- The writer no longer writes any value with `to_s`: a `Date` or a `Time` stops the run and is turned into a String in
  a step.
