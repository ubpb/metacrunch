# metacrunch-csv

CSV for [metacrunch](https://github.com/ubpb/metacrunch): a source that reads CSV files into records and a sink that
writes records as CSV, both on Ruby's `csv`. Values stay Strings, so `"00123"` stays `"00123"`.

```ruby
require "metacrunch/csv"

Metacrunch.job do
  params { args :files, min: 1 }

  source Metacrunch::Csv::Reader.new(params.files), id: ->(record) { record["id"] }

  map { it.merge("year" => Integer(it["year"], exception: false)) }
end
```

```
$ metacrunch run jobs/csv2jsonl.rb books.csv > books.jsonl
```

More in [`examples/`](examples): CSV to JSON Lines, and CSV for Excel.

## Installation

```ruby
# Gemfile
gem "metacrunch-csv"
```

Requires Ruby 4.0 and metacrunch 5. The only other dependency is Ruby's [csv](https://github.com/ruby/csv) gem.

## Reading

```ruby
source Metacrunch::Csv::Reader.new(params.files)                                         # RFC 4180, UTF-8
source Metacrunch::Csv::Reader.new(params.file, col_sep: ";", encoding: "Windows-1252")  # an Excel export
source Metacrunch::Csv::Reader.new(params.file, col_sep: "\t", encoding: "UTF-16LE")     # Excel's "Unicode text"
source Metacrunch::Csv::Reader.new(params.file, headers: ["id", "title"])               # no header row
source Metacrunch::Csv::Reader.new(params.file, headers: false)                         # Array records
```

| Option | Default | |
|---|---|---|
| `col_sep` | `","` | the field separator, any non-empty String |
| `quote_char` | `'"'` | one character, not the separator; one byte in UTF-8 and single-byte encodings |
| `encoding` | `"UTF-8"` | the encoding of the files; values are always UTF-8 |
| `headers` | `true` | `true`: the first row names the columns; an Array of names; `false`: Array records |

The reader reads what `Metacrunch::Input` reads (see metacrunch's
[Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/docs/files.md)): one target or an Array of them —
paths, `"-"` for stdin, or IOs. gzip and tar archives are unpacked; every file in a tar archive has its own header
row. A byte order mark of the encoding (UTF-8, UTF-16LE, UTF-16BE) is removed. The progress display shows how much of
the files has been read.

### Records

| `headers:` | Record | `1,,""` | a row that ends early |
|---|---|---|---|
| `true` or an Array | `{"id" => "1", "b" => "", "c" => ""}` | `""` for empty fields | `nil` for missing fields |
| `false` | `["1", "", ""]` | `""` for empty fields | a shorter Array |

Values are never converted: numbers, dates and ISBNs stay Strings; convert them in a step. Blank lines are skipped.

### Errors

A row that cannot be read becomes a `Metacrunch::InvalidRecord` and fails under the job's failure policy; the rows
after it are read:

| Row | `error` |
|---|---|
| `2,"bad"quote` | `CSV::MalformedCSVError` |
| bytes that are not valid in the encoding (in UTF-8, for example) | `CSV::InvalidEncodingError` |
| a character without a UTF-8 form (byte 0x81 in Windows-1252, for example) | `Encoding::UndefinedConversionError` |
| more fields than the header names | `Metacrunch::Csv::ParseError` (`row has 4 fields, the header 3`) |

`raw` is the row as it stands in the file. A quote that is never closed takes the rest of the file into one
`InvalidRecord`. A file in the wrong encoding shows up as many such rows: `Invalid byte sequence in UTF-8 in line 2.`
means that the file needs `encoding:`.

These stop the run with `Metacrunch::InputError`: a header row that names a column twice, has an empty name (`data.csv:
the header row has an empty column name (column 3)`, often from separators at the end of the line; name the columns
with `headers:`, and the header row comes as the first record) or cannot be read; invalid bytes in UTF-16 (`data.csv:
the data is not valid UTF-16LE`), after which Ruby's csv cannot go on; and errors of the input itself (a missing file,
broken gzip).

### Line ends

Rows end with `"\r\n"`, `"\n"` or `"\r"`, whichever comes first outside quotes in the first 64 KiB of a file; line
breaks inside quoted values are kept. A row that ends differently, such as a single `"\n"` in a file of `"\r\n"`, is an
`InvalidRecord`; its `raw` can then repeat the start of the row, which comes from Ruby's csv (3.3.6).

## Writing

```ruby
sink Metacrunch::Csv::Writer.new(params.target)                                          # columns from the first record
sink Metacrunch::Csv::Writer.new(params.target, columns: ["id", "title"])                # a selection, header = keys
sink Metacrunch::Csv::Writer.new(params.target, columns: {"ID" => "id", "Titel" => "title"},
                                 col_sep: ";", encoding: "Windows-1252")                 # for Excel
```

| Option | Default | |
|---|---|---|
| `columns` | `nil` | `nil`: the keys of the first record; an Array of keys; a Hash of header name => key |
| `header` | `true` | write a header row |
| `col_sep`, `quote_char`, `encoding` | `","`, `'"'`, `"UTF-8"` | as for reading |
| `bom` | `false` | write a byte order mark first (UTF-8, UTF-16LE, UTF-16BE) |

The target is what `Metacrunch::Output` takes: a path (`.gz` compresses), `"-"` for stdout, or an IO. Rows end with
`"\n"`; fields are quoted only where needed.

- With `columns:`, other keys of a record are not written and missing keys are empty fields; the header row is written
  when the run starts, so an empty run gives a file with the header only. A column `"id"` is also found under the key
  `:id`, as in Hashes from a database.
- Without `columns:`, the first record's keys are the columns; a later record with another key stops the run (name the
  columns with `columns:`). An empty run gives an empty file.
- Array records are written as they are; with `columns:` the header comes from it.

| Value | Field |
|---|---|
| `String` | as it is (`""` is written as `""`); Strings in other encodings are converted |
| `Integer`, `Float` | `to_s` |
| `BigDecimal` (from a database's NUMERIC columns) | as a decimal: `123.45` |
| `true`, `false` | `true`, `false` |
| `nil` | empty |

Anything else (a `Time`, a `Date`, an Array) stops the run: `record at position 7: column "date" is a Time; turn it
into a String in a step`. So do a character the target encoding cannot represent and a String that is not valid in
its encoding. `nil` and `""` are both read back as `""`; a row of one empty field is written as `""`, since an empty
line would be skipped when reading.

## Testing jobs

```ruby
records = Metacrunch::Csv::Reader.new(StringIO.new("id,title\n1,Moby\n")).each.to_a
result = Metacrunch::Testing.run(job, source: records)
```

## Upgrading from metacrunch-file

The CSV source and sink of the 4.x gem metacrunch-file are replaced by this gem; its file source and sink by
`Metacrunch::Input` and `Metacrunch::Output` in metacrunch.

| metacrunch-file 4.x | metacrunch-csv |
|---|---|
| `File::CSVSource.new(path, csv_options: {col_sep: ";", file_encoding: "windows-1252"})` | `Csv::Reader.new(path, col_sep: ";", encoding: "Windows-1252")` |
| keys `:id` (downcased Symbols) | keys `"id"`, as in the file |
| `"00123"` read as `123` | `"00123"` |
| empty fields left out of the record | `""` |
| `File::CSVDestination.new(path, override_existing_file: true)` | `Csv::Writer.new(path)` (files are always overwritten) |
| any value is written with `to_s` | a `Date` or `Time` stops the run: turn it into a String in a step |

## License

MIT; see [License.txt](License.txt).
