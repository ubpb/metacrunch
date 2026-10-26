# metacrunch-ng, sub-project 12: metacrunch-csv and metacrunch-xlsx

- Date: 2026-10-25
- Branch: `metacrunch-ng-csv-xlsx` of metacrunch (this spec, later the links in the docs); the gems live in two new
  repositories, `metacrunch-csv` and `metacrunch-xlsx`, next to `metacrunch-marcxml`
- Status: approved design, not implemented; amended while planning (see 1.4)
- Builds on: [sub-project 11 spec](2026-10-25-metacrunch-ng-io-layer-design.md) (`Metacrunch::Input`, `Output`,
  `InputError`, `OutputError`)

## 1. Context

The 4.x gem metacrunch-file held a file source (gzip and tar on the fly), a file sink, a CSV source and sink on
smarter_csv and an XLSX sink on caxlsx. Sub-project 11 moved the file part into core. What is left are the tabular
formats.

In the user's jobs the XLSX sink was the one in real use: 19 report jobs turn a database row into an Array row and
write it to an Excel file with a frozen, filtered header. The CSV classes were never used; two jobs built CSV lines by
hand with `join(";")`.

smarter_csv with metacrunch-file's defaults loses data: `"00123"` becomes `123`, the ISBN `"0306406152"` becomes
`306406152`, keys become downcased Symbols, empty columns disappear. Ruby's `csv` with `headers: true` keeps the
values and gives String keys, as metacrunch's record convention wants.

This sub-project builds two gems, one per format:

- `metacrunch-csv`: `Metacrunch::Csv::Reader` and `Metacrunch::Csv::Writer`, on Ruby's `csv`.
- `metacrunch-xlsx`: `Metacrunch::Xlsx::Writer`, a streaming XLSX writer of its own on zip_kit.

Rejected alternatives:

- **One gem for both** (`metacrunch-tabular`): caxlsx (or any XLSX writer) would come with every CSV install, or the
  XLSX library would be an optional dependency that users add by hand.
- **Keeping the name metacrunch-file:** the name no longer fits once the file layer is in core.
- **CSV in core:** core keeps no runtime dependency besides `logger`; `csv` is a bundled gem since Ruby 3.4 and has to
  be declared.
- **Automatic detection of separator and encoding:** guesses that fail late (a first line with one field, Latin-1
  text without umlauts at the start). Options are explicit instead.
- **Passing Ruby's `csv` options through:** ties the gem's API to Ruby's `csv`, and `converters: :numeric` brings back
  smarter_csv's data loss.
- **caxlsx** keeps the whole workbook in memory (309 MB for 100 000 rows × 10 cells, about 3 GB at Excel's row limit)
  and pulls in nokogiri, rubyzip, marcel and htmlentities. **write_xlsx** needs even more memory (496 MB) and has no
  working constant-memory mode in Ruby. **xlsxtream** streams (28 MB) but has no frozen header and no autofilter, and
  its `auto_format` turns `"00123"` into a number.
- **A shared column model in core or in one of the gems:** a tabular concept core does not need itself, or a
  dependency of the XLSX gem on the CSV gem. Each gem has its own copy (about 40 lines) with the same tests.

### 1.1 Goals

- A CSV source that reads what `Metacrunch::Input` reads, with explicit options, String values and String keys, row
  errors as `InvalidRecord`.
- A CSV sink and an XLSX sink with one column model: `columns:` optional, from the first record otherwise.
- An XLSX sink that streams in constant memory, keeps the 4.x report features (frozen header, autofilter) and writes
  cells by Ruby type, so text stays text.
- Both gems built, tested and documented like `metacrunch-marcxml`.

### 1.2 Non-goals

- Reading XLSX; several worksheets; formulas; date cells; cell styles other than the bold header.
- TSV as a format of its own (it is `col_sep: "\t"`).
- Retiring the 4.x gem metacrunch-file (see 11).
- Creating the GitHub repositories without the user's consent.

### 1.3 Success criteria

- `Metacrunch::Csv::Reader.new("export.csv", col_sep: ";", encoding: "Windows-1252")` yields Hash records with UTF-8
  String values; `"00123"` stays `"00123"`.
- Writer → Reader gives back the same records: Strings and `""`; `nil` comes back as `""`, since the writer writes it
  as an empty field.
- A report job of the 4.x kind (database rows to XLSX) runs with `Metacrunch::Xlsx::Writer` and `columns:`; the file
  opens in Excel without a repair message, with a frozen, bold, filtered header, text as text and numbers as numbers.
- 100 000 rows × 10 cells to XLSX in at most 2 s and below 50 MB peak memory.
- Reading and writing 1 million CSV rows takes at most 1.3 times as long as Ruby's `CSV.foreach` and
  `CSV.generate_line` on the same data.
- Every rule of sections 3 to 7 has a test; line and branch coverage at least 95 % and 90 %; RuboCop with no
  offenses in both gems.

### 1.4 Decisions

Approved by the user on 2026-10-25:

- Two gems, `metacrunch-csv` and `metacrunch-xlsx` (option A of the name question).
- One spec for both; CSV is built first, then XLSX.
- CSV reader: explicit options with RFC 4180 defaults (comma, UTF-8, header row), BOM removed, values in UTF-8
  (option A); a small option set of its own: `col_sep:`, `quote_char:`, `encoding:`, `headers:` (option A); row errors
  are `InvalidRecord`, missing trailing fields `nil`, duplicate or empty column names an `InputError` (option A);
  empty fields `""`, missing fields `nil` (option A).
- Writers: `columns:` optional, the first record defines the columns otherwise (option A).
- XLSX: a streaming writer of its own on zip_kit (option A); cells by Ruby type (option A).
- Column model: one copy per gem (approach A).
- Design sections 1 (gems and layout), 2 (CSV reader), 3 (column model and CSV writer), 4 (XLSX writer, with a bold
  header) and 5 (tests, performance, docs, order), approved one by one.

Found while writing the spec (Ruby 4.0.7, csv 3.3.6):

- `CSV.new` reads its input with `gets(nil, 1024)` and `eof?`; `Input::Stream` needs a small adapter.
- Ruby's `csv` parses in the source encoding (with separators given in it) but does not transcode values to UTF-8,
  also with `encoding: "Windows-1252:UTF-8"` on an IO. The reader transcodes each value itself (3.5).
- `CSV#shift` goes on after `CSV::MalformedCSVError`, and `CSV#line` gives the raw line of the row that failed.

Found while planning, with a prototype of both gems (2026-10-25):

- Ruby's `csv` checks every block it reads with `valid_encoding?` and cannot go on after invalid bytes: it raises the
  same error again on every `shift`. The reader therefore parses UTF-8 and the single-byte encodings as bytes and
  checks each value itself (3.4, 3.5); in other encodings invalid bytes stop the document.
- `csv` reads blocks with `gets(separator, 8192)`. Blocks larger than asked for make reading twice as slow. A block that
  ends inside a character makes valid UTF-16 data fail, as `IO#gets` would never return such a block.
- The line number of `CSV::InvalidEncodingError` counts `csv`'s blocks, not rows.
- `csv` accepts a `col_sep` equal to the `quote_char`; `"x".encode("UTF-16")` adds a byte order mark to every string.
- In Ruby 4.0, `rexml` is a bundled gem: metacrunch-xlsx declares it (and `rubyzip`) for its tests. `roo` does not
  decode `_xHHHH_`, so the escape is checked in the XML.
Found in the final review and decided on 2026-10-26 (the user asked to fix every finding; BigDecimal was decided by
the executor, as the case of the 4.x report jobs, and can be changed):

- Ruby's `csv` detects the row separator from a sample, counting line breaks inside quoted values too; the reader
  passes the first line break outside quotes as `row_sep` (3.3).
- A BigDecimal (NUMERIC columns from a database) is written as a decimal in CSV and as a number in XLSX (5.2, 6.2).
- A signal that wakes the thread inside zlib makes `Zlib::Deflate` raise `Zlib::BufError`, although it keeps the input
  it did not take; zip_kit's `DeflatedWriter` then leaves that piece out of its CRC, so Ctrl-C left broken files. The
  XLSX writer deflates its parts itself (6.4).
- Measured with the prototype: reading 1 million rows 0.96 times and writing 0.41 times Ruby's `csv`; 100 000 rows ×
  10 cells to XLSX in 1.1 s with 43 MB.

## 2. Gems and layout

| | metacrunch-csv | metacrunch-xlsx |
|---|---|---|
| Namespace, require | `Metacrunch::Csv`, `require "metacrunch/csv"` | `Metacrunch::Xlsx`, `require "metacrunch/xlsx"` |
| Runtime dependencies | `metacrunch` (>= 5.0.0.pre, < 6), `csv` (~> 3.3) | `metacrunch` (>= 5.0.0.pre, < 6), `zip_kit` (~> 6.4) |
| Files under `lib/metacrunch/` | `csv.rb`, `csv/version.rb`, `csv/errors.rb`, `csv/columns.rb`, `csv/lines.rb`, `csv/reader.rb`, `csv/writer.rb` | `xlsx.rb`, `xlsx/version.rb`, `xlsx/columns.rb`, `xlsx/cells.rb`, `xlsx/sheet.rb`, `xlsx/package.rb`, `xlsx/writer.rb` |
| Version | `5.0.0.pre` | `5.0.0.pre` |

`Metacrunch::Csv` does not clash with Ruby's `::CSV` (another spelling). The version follows metacrunch and
metacrunch-marcxml: "for metacrunch 5".

As in metacrunch-marcxml:

- gemspec with `required_ruby_version >= 4.0`, `rubygems_mfa_required`, files `lib/**/*.rb`, `CHANGELOG.md`,
  `License.txt` (MIT), `Readme.md`;
- `Gemfile` with `gem "metacrunch", path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")` and the development gems
  (minitest, rake, rubocop-ubpb, simplecov; `roo` for metacrunch-xlsx, see 8.2);
- `Rakefile` (tests with coverage, RuboCop), `.rubocop.yml` inheriting rubocop-ubpb `ruby.yml`;
- `.github/workflows/ci.yml`: Ruby 4.0 and head on Ubuntu and macOS, checking out `ubpb/metacrunch` at
  `metacrunch-ng` into `vendor/metacrunch`;
- `test/unit`, `test/integration`, `test/support`, `bench/`, `examples/` with generic examples.

Repositories: local `~/Code/Projects/upb/metacrunch/metacrunch-csv` and `.../metacrunch-xlsx`, `git init` on branch
`master`. The GitHub repositories `ubpb/metacrunch-csv` and `ubpb/metacrunch-xlsx` are created only with the user's
consent (section 10).

## 3. `Metacrunch::Csv::Reader`

```ruby
source Metacrunch::Csv::Reader.new(params.files)                                         # RFC 4180, UTF-8
source Metacrunch::Csv::Reader.new(params.file, col_sep: ";", encoding: "Windows-1252")  # an Excel export
source Metacrunch::Csv::Reader.new(params.file, headers: ["id", "title"])               # a file without header row
source Metacrunch::Csv::Reader.new(params.file, headers: false)                         # Array records
```

### 3.1 Targets and options

`Reader.new(targets, col_sep: ",", quote_char: '"', encoding: "UTF-8", headers: true)`:

- `targets`: what `Metacrunch::Input.new` takes (paths, `"-"`, IOs, Arrays of them; gzip and tar are unpacked).
- `col_sep`: a non-empty String. `quote_char`: a String of one character other than `col_sep`, one byte in UTF-8 and
  the single-byte encodings (which are parsed as bytes, 3.5). Both must exist in the encoding. `encoding`: a name Ruby's `Encoding.find` knows, of an encoding with a byte order (`UTF-16` and `UTF-32`
  without `LE` or `BE` are refused). `headers`: `true`, `false`, or a non-empty Array of unique, non-empty Strings.
- `new` checks types and values with `ArgumentError` and touches no file.
- Every document is read on its own: in a tar archive of CSV files each file has its own header row.
- `progress` is the input's; `each` without a block returns an Enumerator.

### 3.2 Encoding

- The byte order mark of the chosen encoding is removed at the start of every document: `EF BB BF` for UTF-8,
  `FF FE` for UTF-16LE, `FE FF` for UTF-16BE. Excel's "Unicode text" (UTF-16LE, tab-separated) is
  `encoding: "UTF-16LE", col_sep: "\t"`.
- Values and column names are UTF-8 Strings.

### 3.3 Records

| `headers:` | Record | Empty field (`,,` or `,"",`) | Missing trailing field |
|---|---|---|---|
| `true` (the first row) or an Array | Hash with String keys in column order | `""` | `nil` |
| `false` | Array of Strings | `""` | (a shorter Array) |

- Values are never converted: they stay Strings.
- Blank lines are skipped. A document without rows, and one with a header row only, yields no records.
- Rows end with the first line break outside quotes in the first 64 KiB of a document (`"\r\n"`, `"\n"` or `"\r"`);
  without one there, Ruby's `csv` decides. Quoted line breaks stay in their values.

### 3.4 Errors

A row the reader cannot turn into a record is yielded as `Metacrunch::InvalidRecord.new(raw:, error:)`, so the job's
failure policy decides; reading goes on with the next row:

| Case | `error` |
|---|---|
| Wrong quoting (`2,"bad"quote`) | `CSV::MalformedCSVError` |
| Bytes that are invalid in UTF-8 or a single-byte encoding (ISO-8859-1, Windows-1252, ...), or a value that has no UTF-8 form | `CSV::InvalidEncodingError` or `Encoding::UndefinedConversionError` |
| More fields than columns (`headers:` `true` or an Array) | `Metacrunch::Csv::ParseError` ("row has 4 fields, the header 3") |

- `raw` is the row as it stands in the file (`CSV#line`), transcoded to UTF-8 where possible, else scrubbed.
- An unclosed quote takes the rest of the document with it: the rest is one `InvalidRecord`.
- Invalid bytes in UTF-16, UTF-32 or another multibyte encoding stop the document with a `Metacrunch::InputError`
  (`data.csv: the data is not valid UTF-16LE`): Ruby's `csv` cannot go on after them.
- The header row is checked once per document: a duplicate or an empty column name is a `Metacrunch::InputError`,
  e.g. `data.csv: the header row names the column "a" twice`, `data.csv: the header row has an empty column name
  (column 3)`; so is a header row that cannot be read (`data.csv: the header row cannot be read (...)`). Errors of the
  input itself (a missing file, broken gzip) come from `Input`.

### 3.5 Implementation

- `Metacrunch::Csv::Lines` adapts an `Input::Stream` for `CSV.new`: `gets(separator, limit)` reads up to `limit`
  bytes, tags them with the encoding `csv` parses in and completes a character split at the end of the block, as
  `IO#gets` does; `eof?` asks the stream, `external_encoding`/`internal_encoding` report the encoding. Internal.
- UTF-8 and the single-byte encodings (`Metacrunch::Csv.bytewise?`: no byte of a character looks like ASCII) are
  parsed as bytes, with `col_sep` and `quote_char` as bytes; the reader checks every value against the encoding and
  transcodes it to UTF-8. Other encodings are parsed in the encoding, with the separators encoded into it, and every
  value is transcoded to UTF-8.
- Ruby's `csv` parses with `headers: false`: the reader builds the Hash itself, which gives it the checks of 3.4 and
  the `""`/`nil` rule of 3.3. A value that cannot be transcoded makes its row an `InvalidRecord`.

## 4. The column model (`Columns`, one copy per gem)

The CSV and the XLSX writer turn a record into a row the same way.

- `columns:` is `nil`, an Array of unique, non-empty Strings (the keys, which are also the header), or a Hash of
  header => key with String headers and String keys. Anything else is an `ArgumentError` from `new`.
- **Hash records**, with `columns:`: other keys of a record are not written; missing keys are empty cells. A column is
  found by its key, else by the key as a Symbol, as in Hashes from a database (decided in the final review).
- **Hash records**, without `columns:`: the keys of the first record define the columns, in their order. A later
  record with a key the first one does not have stops the run (`Metacrunch::Error`): `record at position 7 has the
  key "isbn", which the first record does not have; name the columns with columns:`. Missing keys are empty cells.
- **Array records** are written as they are. With `columns:` the header comes from it, and an Array with more values
  than columns is an error. Without `columns:` there is no header (there are no names).
- Hash and Array records in one run are an error.
- `header:` is `true` (written as soon as the names are known) or `false` (no header row).

Errors of the column model and of values (4, 5.2, 6.2, 6.3) are errors of the sink: they stop the job under any
failure policy and name the record's position.

## 5. `Metacrunch::Csv::Writer`

```ruby
sink Metacrunch::Csv::Writer.new(params.output)                                          # columns from the first record
sink Metacrunch::Csv::Writer.new(params.output, columns: ["id", "title"])                # a selection, header = keys
sink Metacrunch::Csv::Writer.new(params.output, columns: {"ID" => "id", "Titel" => "title"},
                                 col_sep: ";", encoding: "Windows-1252", bom: true)      # for Excel
```

### 5.1 Options and output

`Writer.new(target, columns: nil, header: true, col_sep: ",", quote_char: '"', encoding: "UTF-8", bom: false)`:

- `target`: what `Metacrunch::Output.new` takes (a path, `.gz` compressed, `"-"`, an IO). `new` touches no file.
- `col_sep`, `quote_char`, `encoding` as for the reader (3.1); `bom: true` writes the byte order mark of the encoding
  first (UTF-8, UTF-16LE, UTF-16BE; `ArgumentError` for other encodings).
- Rows end with `"\n"`. Fields are quoted only where needed (separator, quote character, line break in the value).
- With `columns:` the header row is written in `open`, so an empty run gives a file with the header only; without
  `columns:` it comes with the first record, and an empty run gives an empty file (with the BOM, if asked for).
- `write_batch` builds the rows and writes them in one piece.

### 5.2 Values

| Value | Field |
|---|---|
| `String` | as it is; Strings in another encoding are converted |
| `Integer`, `Float` | `to_s` |
| `BigDecimal` | a decimal (`to_s("F")`: `123.45`) |
| `true`, `false` | `true`, `false` |
| `nil` | empty; a row of one empty field is written as `""`, as a blank line would be skipped when reading |
| anything else (Time, Date, Array, Hash, other objects) | error: `record at position 7: column "date" is a Time; turn it into a String in a step` |

A character that the target encoding cannot represent is an error with the record's position, not a replacement; so
is a String that is not valid in its own encoding (`record at position 7: column "title" is not valid UTF-8`) or has
no UTF-8 form (a BINARY String with bytes above 127).

## 6. `Metacrunch::Xlsx::Writer`

```ruby
sink Metacrunch::Xlsx::Writer.new("report.xlsx", columns: {"ID" => "id", "Titel" => "title", "Jahr" => "year"},
                                  sheet: "Bestand", widths: {"Titel" => 60})
```

### 6.1 Options

`Writer.new(target, columns: nil, header: true, sheet: "Sheet1", widths: nil)`:

- `target`: what `Metacrunch::Output.new` takes. `"-"` writes the file to stdout (the ZIP container streams).
- `columns:` and `header:` as in section 4.
- `sheet:` the worksheet's name: 1 to 31 characters, none of `[ ] : * ? / \` and no control characters, not starting or
  ending with `'`, with a UTF-8 form (other encodings are converted); `ArgumentError` otherwise.
- `widths:` column widths in characters: a Hash of header name => width, or an Array by position; widths are
  Integers or finite Floats above 0 and up to 255 (Excel's widest column), or `nil` for the default. A name that is not a column is an
  error once the columns are known (in `open` with `columns:`,
  else at the first record). Without `widths:` Excel's default width applies; fitting widths to the content is not
  possible while streaming.

### 6.2 Header and cells

- With a header row, it is bold, frozen (the pane starts at `A2`), and an autofilter covers the header and all data
  rows, as the 4.x reports had it. There are no options for this.
- Cells by Ruby type:

| Value | Cell |
|---|---|
| `String` | text (inline string); `"00123"` stays text. Text of the form `_xHHHH_` is escaped (`_x005F_xHHHH_`, also in chains) so that Excel does not read it as a character code; a carriage return is written as `_x000D_`, as Excel does, since XML would read it as a line feed. A String in another encoding is converted to UTF-8; one that is invalid or has no UTF-8 form is an error. |
| `Integer` with up to 15 digits, finite `Float`, finite `BigDecimal` with up to 15 significant digits | number |
| `true`, `false` | boolean |
| `nil` | empty (no cell is written) |
| `Integer` with more than 15 digits | error: Excel keeps 15 significant digits and would change it silently |
| anything else (Time, Date, Array, Hash, NaN, Infinity, other objects) | error with position and the hint to turn it into a String or number in a step |

### 6.3 Excel's limits

Each is an error with the record's position, not a broken file:

- text with characters XML 1.0 does not allow (control characters other than tab, LF and CR), as in the marcxml
  writer;
- more than 32 767 characters in a cell;
- more than 1 048 576 rows, the header row included;
- more than 16 384 columns.

### 6.4 The file

- Parts: `[Content_Types].xml`, `_rels/.rels`, `xl/workbook.xml` (with the defined name `_xlnm._FilterDatabase` that
  Excel expects for an autofilter), `xl/_rels/workbook.xml.rels`, `xl/styles.xml` (the default style and bold) and
  `xl/worksheets/sheet1.xml`.
- The worksheet is streamed row by row into the ZIP container (zip_kit's streamer over `Metacrunch::Output`); memory
  stays constant. The autofilter range and the workbook are written in `close`, when the last row is known.
- `close` finishes the ZIP container also after an aborted run, with the rows written so far, so the file opens; as the
  marcxml writer writes its `</collection>`. A header row that cannot be written (a control character in a name) and a
  `widths:` name that is not a column stop the run; `close` then finishes the file without a header.
- `write_batch` writes the rows one by one into the compressed stream, which buffers them.
- Every part is deflated by the writer (`Metacrunch::Xlsx::Entry`): it counts CRC and size itself and ignores the
  `Zlib::BufError` a signal causes, and writes into the ZIP container with interrupts held back, so Ctrl-C cannot
  break the file. After SIGPIPE (the reader of a pipe went away) `close` finishes nothing.

## 7. Errors

| Where | Class | When |
|---|---|---|
| `new` of reader and writers | `ArgumentError` | invalid options or targets |
| Reader | `Metacrunch::InvalidRecord` (yielded) | a row: wrong quoting, invalid bytes, no UTF-8 form, too many fields |
| Reader | `Metacrunch::InputError` | the header row: duplicate or empty names, or not readable; invalid bytes in UTF-16 and other multibyte encodings; the input itself (from `Input`) |
| Writers | `Metacrunch::Error` | column model (4), values (5.2, 6.2), Excel's limits (6.3), characters the target encoding lacks (5.2) |
| Writers | `Metacrunch::OutputError`, SIGPIPE | the output itself (from `Output`) |

`Metacrunch::Csv::ParseError < Metacrunch::Error` is the error of an `InvalidRecord` with too many fields.

## 8. Tests and performance

### 8.1 metacrunch-csv

- Reader: option checks; BOM for UTF-8, UTF-16LE, UTF-16BE; Windows-1252 and UTF-16LE to UTF-8; `headers:` `true`,
  `false`, Array; `""` against `nil`; blank lines; every `InvalidRecord` case of 3.4 including an unclosed quote at
  the end and a Windows-1252 byte without UTF-8 form; duplicate and empty column names; gzip, tar (one header row per
  member), Arrays of targets; progress; `each` without a block.
- Columns: the rules of section 4 (the same test file in both gems).
- Writer: the three forms of `columns:`; columns from the first record; the error for a new key; Array records with
  and without `columns:`; mixed records; `header: false`; every value of 5.2 and the error for others; a target
  encoding without a character; `bom:`; quoting; `"\n"`; `.gz`; `"-"`; an empty run with and without `columns:`.
- Round trip: Writer → Reader gives the same records.
- Integration: a job through `Metacrunch::Testing.run` and `Job#run`; the examples run.

### 8.2 metacrunch-xlsx

- Columns: as in 8.1.
- Cells read back with `roo` (a development dependency, with `rubyzip` and `rexml`): text, numbers, booleans, empty
  cells, `"00123"` as text, the
  sheet name, column widths.
- The XML parts parsed one by one with REXML in strict mode: the frozen pane, the autofilter range, the defined name
  `_xlnm._FilterDatabase`, the bold header style, the `_xHHHH_` escape.
- Limits and errors of 6.2 and 6.3; the row and column limits through constants the tests lower.
- An empty run (header only, and no header); an aborted run gives a file `roo` opens; `"-"`.

### 8.3 Performance

- `bench/csv.rb` (metacrunch-csv): 1 million rows read and written; at most 1.3 times Ruby's `CSV.foreach` and
  `CSV.generate_line` on the same data.
- `bench/xlsx.rb` (metacrunch-xlsx): 100 000 rows × 10 cells; at most 2 s and below 50 MB peak memory (measured
  2026-10-25: xlsxtream 1.2 s / 28 MB, caxlsx 2.0 s / 309 MB).

### 8.4 Manual check

The user opens one generated XLSX file in Excel once: no repair message; frozen, bold, filtered header; text as text,
numbers as numbers.

## 9. Documentation

- Each gem: Readme (use in jobs, options, records, errors, limits), CHANGELOG (5.0.0, unreleased), `examples/`
  (generic: CSV to JSON Lines; a report job that writes XLSX).
- metacrunch core: the Readme's paragraph on extension gems and `docs/files.md` name the two gems.

## 10. Order and repositories

1. This spec on the core branch `metacrunch-ng-csv-xlsx`.
2. One plan with tasks: metacrunch-csv completely, then metacrunch-xlsx, then the links in core.
3. The gems are local repositories until the user agrees to create `ubpb/metacrunch-csv` and `ubpb/metacrunch-xlsx`
   on GitHub; their CI can run only after that.

## 11. Deferred

- Reading XLSX; several worksheets; date cells; formulas; more styles.
- Retiring metacrunch-file (a note in its Readme that points to the new gems, and its last 4.x release).
- Further CSV options (for example `liberal_parsing`, `skip_lines`) when a job needs them.
