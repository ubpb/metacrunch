# metacrunch-xlsx

Excel files for [metacrunch](https://github.com/ubpb/metacrunch): a sink that writes records as the rows of one
worksheet. It streams, so memory stays the same for a hundred rows and for a million; the header row is bold, frozen
and filtered; text stays text and numbers are numbers.

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

More in [`examples/`](examples): a report of books.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git", branch: "metacrunch-ng" do
  gem "metacrunch-xlsx"
end
```

Requires Ruby 4.0 and metacrunch in the same version as this gem. The only other dependency is
[zip_kit](https://github.com/julik/zip_kit), which writes the ZIP container.

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
