# metacrunch-xlsx

Excel files for [metacrunch](https://github.com/ubpb/metacrunch): a source that reads the rows of a worksheet as
records, as metacrunch-csv reads CSV, and a sink that writes records as the rows of one worksheet. Both stream, so
memory stays the same for a hundred rows and for a million; text stays text and numbers are numbers. The written
header row is bold, frozen and filtered.

```ruby
require "metacrunch/xlsx"

Metacrunch.job do
  params do
    args :files, min: 1
  end

  # Rows 1 and 2 hold a title, row 3 names the columns.
  source Metacrunch::Xlsx::Reader.new(params.files, sheet: "Bestand", skip: 2)
end
```

```
$ metacrunch run jobs/import.rb books.xlsx > books.jsonl
```

```ruby
require "metacrunch/xlsx"

Metacrunch.job do
  params do
    param :target, String, default: "report.xlsx", desc: "Excel file for the report"
    args :files, min: 1
  end

  source Metacrunch::JsonLines::Reader.new(params.files)

  sink Metacrunch::Xlsx::Writer.new(params.target, columns: {"ID" => "id", "Titel" => "title", "Jahr" => "year"},
                                                   sheet: "Bestand", widths: {"Titel" => 60})
end
```

```
$ metacrunch run jobs/report.rb --target report.xlsx books.jsonl
```

More in [`examples/`](examples): a report of books, and its import back to JSON Lines.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-xlsx"
end
```

Requires Ruby 4.0 and metacrunch in the same version as this gem. The only other dependency is
[zip_kit](https://github.com/julik/zip_kit), which writes the ZIP container; workbooks are read with metacrunch's own
ZIP reader and without an XML library.

## The reader

```ruby
Metacrunch::Xlsx::Reader.new(params.files)                             # the first sheet; row 1 names the columns
Metacrunch::Xlsx::Reader.new(params.files, sheet: 2, headers: false)   # the second sheet, Array records
```

| Option | Default | |
|---|---|---|
| `sheet` | `1` | the sheet: its name, or its position counted from 1 as Excel's tabs are (hidden sheets count) |
| `headers` | `true` | `true`: the first row with a value names the columns; an Array of names: every row is data; `false`: Array records |
| `skip` | `0` | the rows of the sheet before the header or the data, by Excel's row numbers, empty or not: title rows, for example |
| `unpack` | `[:gzip]` | what is unpacked around a workbook: add `:tar` to read the workbooks in tar archives; a workbook is a zip archive itself, so `:zip` is refused |

The reader reads what `Metacrunch::Input` reads (see metacrunch's
[Files](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/files.md)): one target or an Array of them —
paths, `"-"` for stdin, or IOs. A file is read directly; stdin, pipes and workbooks inside gzip or tar go through an
anonymous temporary file, since a workbook is read with random access. Every workbook has its own header row, and
`sheet:` applies to each. The progress display shows how much of the files has been read.

### Records

As `Csv::Reader` gives them:

| `headers:` | Record | an empty cell | a value outside the header's columns |
|---|---|---|---|
| `true` or an Array | `{"id" => "00123", "year" => 2004, "note" => nil}`, every column | `nil` | the row is an invalid record |
| `false` | `["00123", 2004]`, from column A to the last cell with a value | `nil` | — |

- The values of the header row become Strings (`"2024"`, `"2024-11-01"`, `"TRUE"`). It goes from its first to its
  last cell with a value; an empty name between them, or a name used twice, stops the run. Empty columns left of it
  are left out, since tables often start in column B; with `headers:` names, as with `false`, columns count from A.
- Empty rows are skipped, also rows that only have formatting. Hidden rows and columns are read; merged cells have
  their value in the top-left cell.
- A cell holding the empty text is empty, as Excel shows it: formulas such as `=IF(A2="","",A2)` leave it far below
  and right of tables.

### Values

Values are what the cells store, not what Excel shows: a number format such as `0.00 €`, or the text format `@`,
does not change them.

| Cell | Value |
|---|---|
| text | `String`; rich text is joined, line breaks are kept |
| number | `Integer` when it is whole: written with digits only, or below 10^15 (`9783161484100`, `2004`); else `Float` (`1.5`, `1.0e20`) |
| number with a date or time format | an ISO 8601 String without zone: `"2024-11-01"`, `"2024-11-01T14:30:00"`, `"14:30:00"` |
| number with a duration format (`[h]:mm`) | the number of days |
| TRUE, FALSE | `true`, `false` |
| error | its text: `"#N/A"`, `"#DIV/0!"` |
| formula | the last value its writer stored; formulas are not computed |
| empty | `nil` |

Dates are Strings, not `Date`s, so that every sink takes them (JSON Lines refuses a `Date`); a step makes one with
`Date.iso8601(it["date"])`. Seconds are rounded. The 1904 date system of old Mac workbooks is read. A date number that
names no real date (0, Excel's 29 February 1900, after 9999) stays the number.

### Errors

These stop the run with `Metacrunch::InputError`:

- a file that is no workbook: `old.xls: is an Excel 97-2003 workbook (.xls) or an encrypted workbook, which
  metacrunch cannot read; save it as .xlsx first`, the same for binary workbooks (`.xlsb`) and OpenDocument (`.ods`);
  `data.csv: is not an XLSX workbook` for anything else;
- a sheet that is not there (`data.xlsx: has no sheet "Bestand"; its sheets: "Tabelle1", "Daten"`) or is a chart
  sheet;
- a header row that breaks the rules above: `data.xlsx:Bestand: the header row (row 3) has an empty column name
  (column C)`;
- a broken workbook: `data.xlsx: broken XLSX workbook (xl/worksheets/sheet1.xml: unclosed element row)`, and what
  metacrunch says about broken zip archives (a wrong CRC32, for example).

A row with a cell that cannot be read (a shared text that is not there, a number that is none) becomes a
`Metacrunch::InvalidRecord` whose error is a `Metacrunch::Xlsx::ParseError` (`cell C7: number "abc"`) and whose `raw`
is the row's values from column A; the job's failure policy decides, as for a row with a value right of the header.

### Known limits

- The texts a workbook stores once (its shared strings) are kept in memory while its sheet is read; the rows are
  streamed.
- Formulas are not computed: a formula gives the value its writer stored, and none if it stored none, as some
  libraries do.
- Formats, comments, hyperlinks, charts and tables are left out. `.xlsm` and `.xltx` files are read like `.xlsx`.
- Reading 100,000 rows of 10 cells takes about 2.5 s and 51 MB (`bundle exec ruby --yjit bench/reader.rb`).

## The writer

| Option | Default | |
|---|---|---|
| `columns` | `nil` | `nil`: the keys of the first record; an Array of keys; a Hash of header name => key |
| `header` | `true` | write a header row: bold, frozen (the rows scroll below it) and with an autofilter |
| `sheet` | `"Sheet1"` | the worksheet's name: 1 to 31 characters, none of `[ ] : * ? / \` and no control characters, not starting or ending with `'` |
| `widths` | `nil` | column widths in characters (Integers or Floats up to 255): a Hash of header name => width, or an Array by position |

The target is what `Metacrunch::Output` takes: a path, `"-"` for stdout, or an IO. Without `widths:` Excel's default
width applies; a streaming writer cannot fit widths to the content.

### Columns

- With `columns:`, other keys of a record are not written and missing keys are empty cells; the header row is written
  when the run starts, so an empty run gives a file with the header only. A column `"id"` is also found under the key
  `:id`, as in Hashes from a database.
- Without `columns:`, the first record's keys are the columns; a later record with another key stops the run (name the
  columns with `columns:`). An empty run gives an empty sheet.
- Array records are written as they are; with `columns:` the header comes from it, without it there is no header.

### Cells

| Value | Cell |
|---|---|
| `String` | text; `"00123"` stays text; line breaks are kept |
| `Integer` (up to 15 digits), `Float`, `BigDecimal` (up to 15 significant digits, as from a database's NUMERIC columns) | number |
| `true`, `false` | boolean |
| `nil` | empty |

These stop the run with the record's position, e.g. `record at position 7: column "date" is a Time; turn it into a
String or a number in a step`:

- other values: a `Time`, a `Date`, an Array, `NaN`, `Infinity`;
- an Integer with more than 15 digits or a BigDecimal with more than 15 significant digits, which Excel would change
  (it keeps 15 significant digits): write it as a String;
- text with a control character other than tab and line breaks, which XML cannot hold;
- text longer than 32,767 characters, row 1,048,577 (the header counts), more than 16,384 columns: Excel's limits.

When a run aborts, also by Ctrl-C or because the header cannot be written, the writer still finishes the file, with the
rows written so far, so it opens in Excel.

## Upgrading from metacrunch-file

The XLSX sink of the 4.x gem metacrunch-file is replaced by this gem.

| metacrunch-file 4.x | metacrunch-xlsx |
|---|---|
| `File::XLSXDestination.new(path, ["ID", "Titel"], worksheet_title: "Bestand")` | `Xlsx::Writer.new(path, columns: ["ID", "Titel"], sheet: "Bestand")` with Array records |
| every cell is text | cells by Ruby type: turn numbers into Strings in a step to keep them as text |
| `Date` and `Time` become text with `to_s` | they stop the run: turn them into Strings in a step, e.g. `it.strftime("%Y-%m-%d")` |
| `write` takes a row or an Array of rows | one record is one row |
| the workbook is kept in memory until `close` | rows are streamed |

## License

MIT; see [License.txt](License.txt).
