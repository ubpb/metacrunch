# metacrunch-csv and metacrunch-xlsx (sub-project 12) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two extension gems for metacrunch 5 — `metacrunch-csv` (a CSV source and sink on Ruby's `csv`) and `metacrunch-xlsx` (a streaming XLSX sink of its own on zip_kit) — built, tested and documented like metacrunch-marcxml, and named in core's docs.

**Architecture:** `Csv::Reader` reads documents through `Metacrunch::Input`; `Csv::Lines` hands their bytes to Ruby's `CSV` (as bytes for UTF-8 and single-byte encodings, so that a row with invalid bytes is one `InvalidRecord`), and the reader builds Hash records with String values. `Csv::Writer` and `Xlsx::Writer` turn records into rows with a `Columns` model (one copy per gem) and write through `Metacrunch::Output`. The XLSX writer streams the worksheet row by row into a ZIP container (`ZipKit::Streamer`): `Cells` makes the XML of a cell by Ruby type, `Sheet` the worksheet with frozen header and autofilter, `Package` the other parts.

**Tech Stack:** Ruby 4.0, Ruby's `csv` 3.3, zip_kit 6.4, Minitest, RuboCop (rubocop-ubpb), SimpleCov; for the XLSX tests roo, rubyzip and rexml.

**Spec:** `docs/superpowers/specs/2026-10-25-metacrunch-ng-csv-xlsx-design.md` (amended with this plan, see "Amendments to the spec made while planning")

## Global Constraints

- Ruby `>= 4.0`. Runtime dependencies: metacrunch-csv `metacrunch` (`>= 5.0.0.pre`, `< 6`) and `csv` (`~> 3.3`); metacrunch-xlsx `metacrunch` (`>= 5.0.0.pre`, `< 6`) and `zip_kit` (`~> 6.4`). Both gems at version `5.0.0.pre`.
- metacrunch 5 is unreleased: the Gemfiles use `gem "metacrunch", path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")`. The default is the main checkout `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch`, which must be on `metacrunch-ng` at da1c474 or later (it has `Metacrunch::Input` and `Output`).
- Repositories: `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-csv` and `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-xlsx`, new, `git init -b master`. No GitHub repositories (`ubpb/metacrunch-csv`, `ubpb/metacrunch-xlsx`) without the user's consent; never push.
- Core work (Task 11) happens in the worktree `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch/.claude/worktrees/metacrunch-ng-csv-xlsx` (branch `metacrunch-ng-csv-xlsx`).
- `bundle exec rake` passes in every gem after every task: tests under `-w` with no warnings, coverage at least 95 % lines and 90 % branches (the prototype of this plan reached 100 % in every task), RuboCop with no offenses. RuboCop's Minitest rules allow at most 3 assertions per test and want parentheses around assertion arguments that take a block.
- Code, comments, docs and commit messages in English; examples generic (no internal or institution names).
- Error messages exactly as in the code below; tests compare them.
- Every commit ends with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Escapes such as `"\uFEFF"` and `"\u0001"` must stay escapes in the source. File-writing tools may turn them into the raw characters, which look the same or invisible. Before every commit run the invisible-character check from the gem's directory; it must print nothing:

  ```bash
  ruby -e 'ARGV.each { |f| File.read(f, encoding: "UTF-8").each_line.with_index(1) { |l, i| puts "#{f}:#{i}" if l.each_char.any? { |c| o = c.ord; (o < 32 && ![9, 10, 13].include?(o)) || [0xFEFF, 0xFFFD, 0xFFFE, 0xFFFF].include?(o) } } }' $(git ls-files --cached --others --exclude-standard)
  ```

- Performance (spec 1.3): reading and writing 1 million CSV rows at most 1.3 times Ruby's `csv`; 100,000 rows × 10 cells to XLSX in at most 2 s and below 50 MB. The prototype measured 0.96 and 0.41 times, and 1.1 s with 43 MB.

## Review Focus

1. Excel opens a generated file without a repair message, with a bold, frozen, filtered header, text as text and numbers as numbers. Only a person can check it: Task 10, Step 7 asks the user (spec 8.4).
2. A quoted value longer than the 8 KiB blocks Ruby's `csv` reads (100 KB here; 20 MB took 0.02 s in the prototype) comes back whole, and a UTF-16 character split between two blocks does not fail. Tests in Task 3 (`test_a_quoted_value_longer_than_a_block`, `test_utf16_characters_split_between_blocks`).
3. Input from stdin (`"-"`) and old exports with CR-only line ends are read like files. Tests in Task 3 (`test_dash_is_stdin`, `test_cr_line_ends`).
4. A Windows-1252 export read with the default UTF-8: every row with an umlaut becomes an `InvalidRecord`, and its message must name UTF-8 so that the user finds `encoding:`. Test in Task 3 (`test_windows1252_read_as_utf8_names_the_encoding`).
5. Empty and blank Strings in XLSX (`""`, `" "`) and line breaks in a cell: written as text cells, the blank kept. Test in Task 9 (`test_empty_and_blank_strings_are_text_cells`).

## Amendments to the spec made while planning

A prototype of both gems (all code below, run task by task) found these; the spec is amended in the same commit as this plan:

- Ruby's `csv` checks every block it reads with `valid_encoding?` and cannot go on after invalid bytes: it raises the same error again on every `shift`. The reader parses UTF-8 and the single-byte encodings (ISO-8859-1, Windows-1252, ...: `Csv.bytewise?`) as bytes and checks each value itself; invalid bytes in UTF-16, UTF-32 and other multibyte encodings stop the document with `InputError` (`StringIO: the data is not valid UTF-16LE`), without a line number, since `csv`'s line number counts blocks.
- `Lines#gets` reads what `csv` asks for (8 KiB): 64 KiB blocks made reading twice as slow. It completes a character split at the end of a block, as `IO#gets` does; without that, valid UTF-16 with emoji failed.
- A header row that cannot be read is an `InputError` (`StringIO: the header row cannot be read (...)`); otherwise the next row would silently become the header.
- `quote_char` must differ from `col_sep`, both must exist in the encoding, and `UTF-16` or `UTF-32` without byte order are an `ArgumentError` (`"x".encode("UTF-16")` adds a byte order mark to every String).
- Writers: a String that is not valid in its encoding is an error (`record at position 1: column "t" is not valid UTF-8`); the CSV writer wrote it silently, the XLSX writer raised a bare `EncodingError`. XLSX converts Strings of other encodings to UTF-8.
- `nil` written by the CSV writer comes back as `""` (spec 1.3 said `nil`).
- XLSX `widths:` are numbers above 0 and up to 255 (Excel's widest column).
- XLSX `write_batch` writes the rows one by one into the compressed stream, which buffers them; the spec said "in one piece".
- XLSX: a header that cannot be written (a control character in a column name) and a `widths:` name that is not a column stop the run; `close` then finishes a file without header. Found: the first version wrote the start of the sheet again in `close` and raised there, leaving a broken file.
- metacrunch-xlsx declares `rexml` (a bundled gem in Ruby 4.0) and `rubyzip` for its tests; `roo` does not decode `_xHHHH_`, so that escape is checked in the XML.

Also found and fixed in the prototype (no spec change): heredoc constants (`<<~XML.delete("\n")`) were not frozen, so `+HEAD` handed out the constant itself and every writer appended to it; `Sheet#row` counted a row that then failed, which moved the autofilter range; messages said "a Array" (now `Columns.described`: "an Array").

## File Structure

metacrunch-csv (`/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-csv`):

| File | Responsibility | Task |
|---|---|---|
| `metacrunch-csv.gemspec`, `Gemfile`, `Rakefile`, `.rubocop.yml`, `.gitignore`, `License.txt`, `.github/workflows/ci.yml` | The gem, as metacrunch-marcxml | 1 |
| `lib/metacrunch/csv.rb` | Requires; `Csv::BOMS`, `Csv.encoding` (option checks), `Csv.bytewise?` | 1–4 |
| `lib/metacrunch/csv/version.rb` | `VERSION` | 1 |
| `lib/metacrunch/csv/columns.rb` | The column model of the writer; `Columns.described` | 2 |
| `lib/metacrunch/csv/errors.rb` | `ParseError` | 3 |
| `lib/metacrunch/csv/lines.rb` | An `Input::Stream` as Ruby's `CSV` reads it | 3 |
| `lib/metacrunch/csv/reader.rb` | The source | 3 |
| `lib/metacrunch/csv/writer.rb` | The sink | 4 |
| `test/test_helper.rb`, `test/support/helpers.rb` | SimpleCov, requires; `ctx`, `read`, `written`, `write_error`, `tar` | 1 |
| `test/unit/csv_test.rb`, `columns_test.rb`, `lines_test.rb`, `reader_test.rb`, `writer_test.rb` | Unit tests | 1–4 |
| `test/integration/round_trip_test.rb`, `jobs_test.rb`, `examples_test.rb` | Writer → Reader; jobs; examples | 4, 5 |
| `examples/csv2jsonl.rb`, `examples/books2excel.rb`, `examples/data/books.csv` | Generic examples | 5 |
| `bench/csv.rb` | 1 million rows against Ruby's `csv` | 5 |
| `Readme.md`, `CHANGELOG.md` | Docs | 5 |

metacrunch-xlsx (`/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-xlsx`):

| File | Responsibility | Task |
|---|---|---|
| `metacrunch-xlsx.gemspec`, `Gemfile`, `Rakefile`, `.rubocop.yml`, `.gitignore`, `License.txt`, `.github/workflows/ci.yml` | The gem | 6 |
| `lib/metacrunch/xlsx.rb`, `lib/metacrunch/xlsx/version.rb` | Requires; `VERSION` | 6–9 |
| `lib/metacrunch/xlsx/columns.rb` | The column model, the same as metacrunch-csv's but for the namespace | 6 |
| `lib/metacrunch/xlsx/cells.rb` | Column letters; the XML of a cell by Ruby type; `Cells::Unwritable` | 7 |
| `lib/metacrunch/xlsx/sheet.rb` | The worksheet: start (frozen header, widths), rows, end (autofilter); Excel's row and column limits | 8 |
| `lib/metacrunch/xlsx/package.rb` | The other parts: content types, relationships, styles, workbook | 8 |
| `lib/metacrunch/xlsx/writer.rb` | The sink on `Output` and `ZipKit::Streamer` | 9 |
| `test/test_helper.rb`, `test/support/helpers.rb` | SimpleCov, requires (roo quietly); `ctx`, `xlsx`, `write_error`, `rows`, `parts`, `sheet_xml`, `with_limit` | 6 |
| `test/unit/columns_test.rb`, `cells_test.rb`, `sheet_test.rb`, `package_test.rb`, `writer_test.rb` | Unit tests | 6–9 |
| `test/integration/jobs_test.rb`, `examples_test.rb` | Jobs; the example | 10 |
| `examples/report.rb`, `examples/data/books.jsonl` | A generic report | 10 |
| `bench/xlsx.rb` | 100,000 rows × 10 cells | 10 |
| `Readme.md`, `CHANGELOG.md` | Docs | 10 |

metacrunch core (worktree): `Readme.md` and `docs/files.md` name the gems (Task 11).

Task order: 1 → 2 → … → 11. How to run one test file (from the gem's directory):

```bash
bundle exec ruby -w -Itest -Ilib test/unit/csv_test.rb
```

Session note: the work runs in the core worktree, while Tasks 1–10 write to the two new repositories. If the session's worktree isolation refuses edits or commands there, leave the worktree with ExitWorktree (keep) for Tasks 1–10 and enter it again with EnterWorktree (`path:` the core worktree) for Task 11.

---

### Task 1: metacrunch-csv: the gem, `Csv.encoding` and `Csv.bytewise?`

**Files:**
- Create: `metacrunch-csv.gemspec`, `Gemfile`, `Rakefile`, `.rubocop.yml`, `.gitignore`, `License.txt`, `.github/workflows/ci.yml`, `lib/metacrunch/csv/version.rb`, `lib/metacrunch/csv.rb`
- Test: `test/test_helper.rb`, `test/support/helpers.rb`, `test/unit/csv_test.rb`

**Interfaces:**
- Produces: `Metacrunch::Csv::VERSION = "5.0.0.pre"`; `Metacrunch::Csv::BOMS` (Encoding => binary BOM for UTF-8, UTF-16LE, UTF-16BE); `Metacrunch::Csv.encoding(col_sep, quote_char, encoding) -> Encoding` (raises `ArgumentError`); `Metacrunch::Csv.bytewise?(encoding) -> true/false`.
- Test helpers for later tasks (`test/support/helpers.rb`, a module `Helpers`): `ctx(position = 1)`, `read(bytes, **options)` (records of `Csv::Reader` over a StringIO, Task 3), `written(records, **options)` (bytes of `Csv::Writer`, Task 4), `write_error(records, **options)`, `tar(name => content)`.

- [ ] **Step 1: Create the repository**

```bash
mkdir -p /Users/renspr/Code/Projects/upb/metacrunch/metacrunch-csv
git -C /Users/renspr/Code/Projects/upb/metacrunch/metacrunch-csv init -b master
```

All later commands of Tasks 1–5 run in `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-csv`.

- [ ] **Step 2: Write the gem's files**

`metacrunch-csv.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/metacrunch/csv/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-csv"
  spec.version  = Metacrunch::Csv::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "CSV for metacrunch: a source and a sink on Ruby's csv"
  spec.homepage = "https://github.com/ubpb/metacrunch-csv"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"
end
```

`Gemfile`:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# metacrunch 5 is not released yet. METACRUNCH_PATH points to a checkout of
# its metacrunch-ng branch; by default it lies next to this repository.
gem "metacrunch", path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")

group :development do
  gem "minitest", ">= 5.25"
  gem "rake", ">= 13.0"
  gem "rubocop-ubpb", github: "ubpb/rubocop-ubpb", require: false
  gem "simplecov", ">= 0.22", require: false
end
```

`Rakefile`:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

# Coverage thresholds apply to full runs only (see test/test_helper.rb).
ENV["COVERAGE"] = "1" unless ENV.key?("COVERAGE")

Minitest::TestTask.create do |t|
  t.test_globs = ["test/**/*_test.rb"]
end

RuboCop::RakeTask.new

task default: [:test, :rubocop]
```

`.rubocop.yml`:

```yaml
inherit_gem:
  rubocop-ubpb: ruby.yml

inherit_mode:
  merge:
    - Exclude

Style/FrozenStringLiteralComment:
  Enabled: true

# Tests leave loops on purpose (`each_document { return ... }`).
Lint/UnreachableLoop:
  Exclude:
    - "test/**/*"
```

`.gitignore`:

```
/.bundle/
/coverage/
/pkg/
/tmp/
/vendor/
Gemfile.lock
.DS_Store
```

`License.txt`:

```
Copyright (c) 2026 René Sprotte

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

`.github/workflows/ci.yml` (as metacrunch-marcxml's, for branch `master`; it runs once the repository is on GitHub):

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

permissions:
  contents: read

env:
  # metacrunch 5 is not released yet; see the Gemfile.
  METACRUNCH_PATH: vendor/metacrunch

jobs:
  test:
    name: Test (Ruby ${{ matrix.ruby }}, ${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    continue-on-error: ${{ matrix.ruby == 'head' }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        ruby: ["4.0", head]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: ubpb/metacrunch
          ref: metacrunch-ng
          path: vendor/metacrunch
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rake test

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: ubpb/metacrunch
          ref: metacrunch-ng
          path: vendor/metacrunch
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: "4.0"
          bundler-cache: true
      - run: bundle exec rubocop
```

`lib/metacrunch/csv/version.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Csv

    VERSION = "5.0.0.pre"

  end
end
```

- [ ] **Step 3: Install the bundle**

Run: `bundle install`
Expected: `Bundle complete!` (`Gemfile.lock` is ignored by git).

- [ ] **Step 4: Write the failing test**

`test/test_helper.rb`:

```ruby
# frozen_string_literal: true

if ENV.key?("COVERAGE")
  require "simplecov"

  SimpleCov.start do
    # One run is one result: no merging with results of earlier runs.
    merging false
    enable_coverage :branch
    minimum_coverage line: 95, branch: 90
    skip "/test/"
    skip "/vendor/"
  end
end

require "minitest/autorun"
require "logger"
require "stringio"
require "tmpdir"
require "fileutils"
require "zlib"
require "rubygems/package"
require "metacrunch/csv"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
```

`test/support/helpers.rb`:

```ruby
# frozen_string_literal: true

# Helpers shared by the tests.
module Helpers

  # A context as the engine passes it to a sink.
  def ctx(position = 1) = Metacrunch::Context.new(id: position, position:, logger: Logger.new(nil))

  # The records the reader yields for bytes.
  def read(bytes, **) = Metacrunch::Csv::Reader.new(StringIO.new(bytes.b), **).each.to_a

  # The bytes the writer writes for records.
  def written(records, **)
    io = StringIO.new("".b)
    writer = Metacrunch::Csv::Writer.new(io, **)
    writer.open(nil)
    records.each_with_index { |record, index| writer.write(record, ctx(index + 1)) }
    writer.close
    io.string
  end

  # The error the writer raises for records.
  def write_error(records, **) = assert_raises(Metacrunch::Error) { written(records, **) }

  # A tar archive of name => content.
  def tar(files)
    io = StringIO.new("".b)
    Gem::Package::TarWriter.new(io) do |tar|
      files.each { |name, content| tar.add_file_simple(name, 0o644, content.bytesize) { it.write(content) } }
    end
    io.string
  end

end
```

`test/unit/csv_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CsvTest < Minitest::Test

  Csv = Metacrunch::Csv

  def test_encoding_finds_the_encoding
    assert_equal Encoding::Windows_1252, Csv.encoding(";", '"', "Windows-1252")
  end

  def test_an_unknown_encoding_is_an_argument_error
    error = assert_raises(ArgumentError) { Csv.encoding(",", '"', "Klingon") }

    assert_equal 'encoding must be the name of an encoding, got "Klingon"', error.message
  end

  def test_an_encoding_without_byte_order_is_an_argument_error
    error = assert_raises(ArgumentError) { Csv.encoding(",", '"', "UTF-16") }

    assert_equal "encoding UTF-16 has no byte order; use UTF-16LE, UTF-16BE or another encoding", error.message
  end

  def test_col_sep_is_a_non_empty_string
    [nil, "", 1].each do |col_sep|
      assert_raises(ArgumentError) { Csv.encoding(col_sep, '"', "UTF-8") }
    end
  end

  def test_quote_char_is_one_character_other_than_col_sep
    [nil, "", "''", ","].each do |quote_char|
      assert_raises(ArgumentError) { Csv.encoding(",", quote_char, "UTF-8") }
    end
  end

  def test_separators_must_exist_in_the_encoding
    error = assert_raises(ArgumentError) { Csv.encoding("€", '"', "ISO-8859-1") }

    assert_equal '"€" cannot be written in ISO-8859-1', error.message
  end

  def test_utf8_and_single_byte_encodings_are_bytewise
    assert(["UTF-8", "ISO-8859-1", "Windows-1252", "IBM437"].all? { Csv.bytewise?(Encoding.find(it)) })
  end

  def test_other_encodings_are_not_bytewise
    assert(["UTF-16LE", "UTF-16BE", "Shift_JIS", "GB18030"].none? { Csv.bytewise?(Encoding.find(it)) })
  end

end
```

- [ ] **Step 5: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/csv_test.rb`
Expected: `cannot load such file -- metacrunch/csv (LoadError)`.

- [ ] **Step 6: Write `lib/metacrunch/csv.rb`**

```ruby
# frozen_string_literal: true

require "csv"
require "stringio"
require "metacrunch"
require_relative "csv/version"

module Metacrunch
  # CSV for metacrunch: a source (Reader) and a sink (Writer) on Ruby's csv.
  # Records are Hashes with String keys (or Arrays); values stay Strings.
  module Csv

    # The byte order marks the reader removes and the writer can write.
    BOMS = {
      Encoding::UTF_8 => "\xEF\xBB\xBF".b,
      Encoding::UTF_16LE => "\xFF\xFE".b,
      Encoding::UTF_16BE => "\xFE\xFF".b
    }.freeze

    class << self

      # The Encoding named encoding; raises ArgumentError unless col_sep and
      # quote_char are usable with it.
      def encoding(col_sep, quote_char, encoding)
        found = find(encoding)
        unless col_sep.is_a?(String) && !col_sep.empty?
          raise ArgumentError, "col_sep must be a non-empty String, got #{col_sep.inspect}"
        end
        unless quote_char.is_a?(String) && quote_char.length == 1 && quote_char != col_sep
          raise ArgumentError, "quote_char must be one character other than col_sep, got #{quote_char.inspect}"
        end

        [col_sep, quote_char].each { encodable(it, found) }
        found
      end

      # True for UTF-8 and the single-byte encodings (ISO-8859-1,
      # Windows-1252, ...): no byte of a character there looks like ASCII,
      # so Ruby's csv can parse the bytes.
      def bytewise?(encoding)
        return true if encoding == Encoding::UTF_8

        encoding.ascii_compatible? && (0x80..0xFF).all? { [it].pack("C").force_encoding(encoding).valid_encoding? }
      end

      private

      def find(name)
        encoding = begin
          Encoding.find(name)
        rescue ArgumentError, TypeError
          raise ArgumentError, "encoding must be the name of an encoding, got #{name.inspect}"
        end
        return encoding unless encoding.dummy?

        raise ArgumentError, "encoding #{encoding} has no byte order; use UTF-16LE, UTF-16BE or another encoding"
      end

      def encodable(text, encoding)
        text.encode(encoding)
      rescue EncodingError
        raise ArgumentError, "#{text.inspect} cannot be written in #{encoding}"
      end

    end

  end
end
```

Tasks 2–4 add their `require_relative` lines below `require_relative "csv/version"`.

- [ ] **Step 7: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/csv_test.rb`
Expected: `8 runs, 16 assertions, 0 failures, 0 errors, 0 skips`, no warnings.

- [ ] **Step 8: Run the whole gem**

Run: `bundle exec rake`
Expected: `8 runs, 0 failures`; `Line coverage: 28 / 28 (100.00%)`, `Branch coverage: 8 / 8 (100.00%)`; `no offenses detected`.

- [ ] **Step 9: Commit**

Run the invisible-character check (Global Constraints), then:

```bash
git add -A
git commit -m "Set up metacrunch-csv with the checks of its options

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: metacrunch-csv: `Columns`

**Files:**
- Create: `lib/metacrunch/csv/columns.rb`
- Modify: `lib/metacrunch/csv.rb` (one `require_relative`)
- Test: `test/unit/columns_test.rb`

**Interfaces:**
- Consumes: `Helpers#ctx` (Task 1).
- Produces: `Metacrunch::Csv::Columns.new(columns)` (`nil`, Array of names, Hash of header => key; `ArgumentError` otherwise); `#names -> Array<String> or nil`; `#known? -> true/false`; `#row(record, ctx) -> Array` (values in column order; learns the columns from the first Hash record; raises `Metacrunch::Error`); `Columns.described(object) -> "a Time" / "an Array"`. Task 4 (`Csv::Writer`) and Task 6 (the copy in metacrunch-xlsx) rely on these.

- [ ] **Step 1: Write the failing test**

`test/unit/columns_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# The same tests as in metacrunch-xlsx; only this constant differs.
class ColumnsTest < Minitest::Test

  Columns = Metacrunch::Csv::Columns

  include Helpers

  def test_without_columns_nothing_is_known
    columns = Columns.new(nil)

    refute_predicate columns, :known?
    assert_nil columns.names
  end

  def test_an_array_names_the_keys_and_the_header
    columns = Columns.new(["id", "title"])

    assert_equal ["id", "title"], columns.names
    assert_equal ["2", "Moby"], columns.row({"title" => "Moby", "id" => "2", "year" => "1851"}, ctx)
  end

  def test_a_hash_maps_header_names_to_keys
    columns = Columns.new({"ID" => "id", "Titel" => "title"})

    assert_equal ["ID", "Titel"], columns.names
    assert_equal ["2", "Moby"], columns.row({"title" => "Moby", "id" => "2"}, ctx)
  end

  def test_missing_keys_are_nil
    assert_equal ["2", nil], Columns.new(["id", "title"]).row({"id" => "2"}, ctx)
  end

  def test_invalid_columns_are_argument_errors
    [:id, "id", [], ["a", "a"], ["", "b"], [1], {"A" => 1}, {"A" => ""}, {a: "a"}].each do |columns|
      assert_raises(ArgumentError) { Columns.new(columns) }
    end
  end

  def test_a_named_column_twice_names_it
    error = assert_raises(ArgumentError) { Columns.new(["a", "b", "a"]) }

    assert_equal 'the column "a" is named twice', error.message
  end

  def test_the_first_record_defines_the_columns
    columns = Columns.new(nil)
    columns.row({"id" => "1", "title" => "Moby"}, ctx)

    assert_equal ["id", "title"], columns.names
    assert_equal ["2", nil], columns.row({"id" => "2"}, ctx(2))
  end

  def test_symbol_keys_give_string_names
    columns = Columns.new(nil)

    assert_equal ["1"], columns.row({id: "1"}, ctx)
    assert_equal ["id"], columns.names
  end

  def test_a_new_key_without_columns_stops_the_run
    columns = Columns.new(nil)
    columns.row({"id" => "1"}, ctx)
    error = assert_raises(Metacrunch::Error) { columns.row({"id" => "7", "isbn" => "x"}, ctx(7)) }

    assert_equal 'record at position 7 has the key "isbn", which the first record does not have; ' \
                 "name the columns with columns:", error.message
  end

  def test_with_columns_other_keys_are_ignored
    assert_equal ["1"], Columns.new(["id"]).row({"id" => "1", "isbn" => "x"}, ctx)
  end

  def test_arrays_are_rows_as_they_are
    columns = Columns.new(nil)

    assert_equal ["1", 2], columns.row(["1", 2], ctx)
    refute_predicate columns, :known?
  end

  def test_an_array_longer_than_the_columns_is_an_error
    error = assert_raises(Metacrunch::Error) { Columns.new(["a", "b"]).row([1, 2, 3], ctx(4)) }

    assert_equal "record at position 4 has 3 values for 2 columns", error.message
  end

  def test_hashes_and_arrays_do_not_mix
    columns = Columns.new(nil)
    columns.row({"a" => 1}, ctx)
    error = assert_raises(Metacrunch::Error) { columns.row([1], ctx(2)) }

    assert_equal "record at position 2 is an Array, the records before it are Hashes; write either Hashes or Arrays",
                 error.message
  end

  def test_arrays_and_hashes_do_not_mix
    columns = Columns.new(nil)
    columns.row([1], ctx)
    error = assert_raises(Metacrunch::Error) { columns.row({"a" => 1}, ctx(2)) }

    assert_match(/is a Hash, the records before it are Arrays/, error.message)
  end

  def test_other_records_are_errors
    error = assert_raises(Metacrunch::Error) { Columns.new(nil).row("1,2", ctx(3)) }

    assert_equal "record at position 3 is a String, not a Hash or an Array", error.message
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/columns_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Csv::Columns (NameError)`.

- [ ] **Step 3: Write `lib/metacrunch/csv/columns.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Csv
    # Turns records into rows: the columns: of a writer, or the keys of the
    # first Hash record. The same rules hold in metacrunch-xlsx.
    class Columns

      PLURALS = {Hash => "Hashes", Array => "Arrays"}.freeze

      # "a Time", "an Array": the class of object with its article.
      def self.described(object)
        name = object.class.name
        "#{name.match?(/\A[AEIOU]/) ? "an" : "a"} #{name}"
      end

      # columns: nil, an Array of unique, non-empty Strings (keys, also the
      # header), or a Hash of header => key.
      def initialize(columns)
        @names, @keys = parse(columns)
        @given = !@keys.nil?
        @kind = nil
      end

      # The header names, or nil while they are not known.
      attr_reader :names

      def known? = !@names.nil?

      # The values of record in column order. Learns the columns from the
      # first Hash record when none were given.
      def row(record, ctx)
        kind = record_kind(record, ctx)
        kind == Hash ? hash_row(record, ctx) : array_row(record, ctx)
      end

      private

      def parse(columns)
        case columns
        when nil then [nil, nil]
        when Array then [check_names(columns), columns]
        when Hash then [check_names(columns.keys), check_keys(columns.values)]
        else raise ArgumentError, "columns must be nil, an Array or a Hash, got #{columns.inspect}"
        end
      end

      def check_names(names)
        unless names.all? { it.is_a?(String) && !it.empty? }
          raise ArgumentError, "column names must be non-empty Strings, got #{names.inspect}"
        end
        raise ArgumentError, "columns must not be empty" if names.empty?

        duplicate = names.find { names.count(it) > 1 }
        raise ArgumentError, "the column #{duplicate.inspect} is named twice" if duplicate

        names
      end

      def check_keys(keys)
        return keys if keys.all? { it.is_a?(String) && !it.empty? }

        raise ArgumentError, "column keys must be non-empty Strings, got #{keys.inspect}"
      end

      # Hash or Array; the first record decides for the run.
      def record_kind(record, ctx)
        kind = [Hash, Array].find { record.is_a?(it) }
        unless kind
          raise Metacrunch::Error, "record at position #{ctx.position} is #{Columns.described(record)}, " \
                                   "not a Hash or an Array"
        end
        @kind ||= kind
        return kind if kind == @kind

        raise Metacrunch::Error, "record at position #{ctx.position} is #{Columns.described(record)}, the records " \
                                 "before it are #{PLURALS[@kind]}; write either Hashes or Arrays"
      end

      def hash_row(record, ctx)
        unless @keys
          @keys = record.keys
          @names = @keys.map(&:to_s)
        end
        check_new_keys(record, ctx) unless @given
        @keys.map { record[it] }
      end

      def check_new_keys(record, ctx)
        return if record.size <= @keys.size && record.each_key.all? { @keys.include?(it) }

        key = record.each_key.find { !@keys.include?(it) }
        raise Metacrunch::Error, "record at position #{ctx.position} has the key #{key.inspect}, which the first " \
                                 "record does not have; name the columns with columns:"
      end

      def array_row(record, ctx)
        return record unless @keys && record.size > @keys.size

        raise Metacrunch::Error, "record at position #{ctx.position} has #{record.size} values for " \
                                 "#{@keys.size} columns"
      end

    end
  end
end
```

In `lib/metacrunch/csv.rb`, below `require_relative "csv/version"`, add:

```ruby
require_relative "csv/columns"
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/columns_test.rb`
Expected: `15 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `23 runs, 0 failures`; `Line coverage: 82 / 82 (100.00%)`; `no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add Columns, the column model of the writer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: metacrunch-csv: `Lines` and `Reader`

**Files:**
- Create: `lib/metacrunch/csv/errors.rb`, `lib/metacrunch/csv/lines.rb`, `lib/metacrunch/csv/reader.rb`
- Modify: `lib/metacrunch/csv.rb` (three `require_relative`)
- Test: `test/unit/lines_test.rb`, `test/unit/reader_test.rb`

**Interfaces:**
- Consumes: `Csv.encoding`, `Csv.bytewise?`, `Csv::BOMS` (Task 1); `Metacrunch::Input#each_document { |stream, name| }`, `Input::Stream#read(n)`, `#peek(n)`, `#eof?`, `Input#progress` (core); `Helpers#read`, `#tar` (Task 1).
- Produces: `Metacrunch::Csv::ParseError < Metacrunch::Error`; `Metacrunch::Csv::Lines.new(stream, encoding)` with `gets(separator = nil, limit = BLOCK)`, `eof?`, `external_encoding`, `internal_encoding`; `Metacrunch::Csv::Reader.new(targets, col_sep: ",", quote_char: '"', encoding: "UTF-8", headers: true)` with `each` (Enumerator without a block) and `progress`. Tasks 4 and 5 use the reader.

- [ ] **Step 1: Write the failing test for `Lines`**

`test/unit/lines_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class LinesTest < Minitest::Test

  def test_gets_reads_up_to_the_limit_in_the_encoding
    block = lines("abc", Encoding::BINARY) { it.gets(nil, 2) }

    assert_equal "ab".b, block
    assert_equal Encoding::BINARY, block.encoding
  end

  def test_gets_returns_nil_at_the_end
    assert_nil(lines("", Encoding::UTF_8) { it.gets(nil, 10) })
  end

  def test_gets_without_a_limit_reads_a_block
    assert_equal "a" * Metacrunch::Csv::Lines::BLOCK, lines("a" * 70_000, Encoding::UTF_8, &:gets)
  end

  def test_a_character_split_by_the_limit_is_completed
    emoji = "😀".encode(Encoding::UTF_16LE)
    block = lines(emoji, Encoding::UTF_16LE) { it.gets(nil, 2) }

    assert_equal emoji, block
  end

  def test_invalid_bytes_stay_invalid
    block = lines("\x00\xD8a\x00b\x00c\x00".b, Encoding::UTF_16LE) { it.gets(nil, 2) }

    refute_predicate block, :valid_encoding?
    assert_equal 5, block.bytesize
  end

  def test_the_encodings_csv_asks_for
    encodings = lines("", Encoding::UTF_16LE) { [it.external_encoding, it.internal_encoding] }

    assert_equal [Encoding::UTF_16LE, nil], encodings
  end

  def test_eof_asks_the_stream
    assert(lines("a", Encoding::UTF_8) { [it.eof?, it.gets(nil, 1), it.eof?] == [false, "a", true] })
  end

  private

  # Yields Lines over bytes and returns what the block returns.
  def lines(bytes, encoding)
    Metacrunch::Input.new(StringIO.new(bytes.b)).each_document do |stream, _name|
      return yield Metacrunch::Csv::Lines.new(stream, encoding)
    end
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/lines_test.rb`
Expected: errors with `NameError: uninitialized constant Metacrunch::Csv::Lines`.

- [ ] **Step 3: Write `lib/metacrunch/csv/lines.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Csv
    # The bytes of a Metacrunch::Input::Stream as Ruby's CSV reads its
    # input: gets and eof?. Blocks are tagged with the encoding and, as with
    # IO#gets, never end inside a character. Internal.
    class Lines

      BLOCK = 65_536

      def initialize(stream, encoding)
        @stream = stream
        @encoding = encoding
        @binary = encoding == Encoding::BINARY
      end

      # The next block of up to limit bytes. CSV's separator does not
      # matter: it splits rows itself.
      def gets(_separator = nil, limit = BLOCK)
        data = @stream.read(limit)
        return if data.nil?

        data.force_encoding(@encoding)
        @binary || data.valid_encoding? ? data : complete(data)
      end

      def eof? = @stream.eof?

      def external_encoding = @encoding

      def internal_encoding = nil

      private

      # Adds up to three bytes, as many as a character split at the end of
      # the block needs. Invalid bytes elsewhere stay invalid.
      def complete(data)
        bytes = data.b
        3.times do
          break if @stream.eof?

          bytes << @stream.read(1)
          break if bytes.dup.force_encoding(@encoding).valid_encoding?
        end
        bytes.force_encoding(@encoding)
      end

    end
  end
end
```

In `lib/metacrunch/csv.rb`, below `require_relative "csv/columns"`, add:

```ruby
require_relative "csv/lines"
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/lines_test.rb`
Expected: `7 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Write the failing test for `Reader`**

`test/unit/reader_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ReaderTest < Minitest::Test

  include Helpers

  Reader = Metacrunch::Csv::Reader

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Options

  def test_new_touches_no_file
    assert_instance_of Reader, Reader.new(File.join(@dir, "missing.csv"))
  end

  def test_headers_must_be_true_false_or_names
    [nil, "id", [], ["a", "a"], ["", "b"], [:a]].each do |headers|
      assert_raises(ArgumentError) { Reader.new("data.csv", headers:) }
    end
  end

  def test_options_are_checked_by_new
    assert_raises(ArgumentError) { Reader.new("data.csv", encoding: "UTF-16") }
    assert_raises(ArgumentError) { Reader.new("data.csv", col_sep: "") }
  end

  # Records

  def test_records_are_hashes_with_string_keys_and_values
    assert_equal [{"id" => "1", "title" => "Moby"}], read("id,title\n1,Moby\n")
  end

  def test_empty_fields_are_empty_strings_and_missing_fields_nil
    assert_equal [{"a" => "1", "b" => "", "c" => ""}, {"a" => "2", "b" => nil, "c" => nil}],
                 read(%(a,b,c\n1,,""\n2\n))
  end

  def test_values_are_never_converted
    assert_equal [{"id" => "00123", "isbn" => "0306406152", "year" => "1851"}],
                 read("id,isbn,year\n00123,0306406152,1851\n")
  end

  def test_blank_lines_are_skipped
    assert_equal [{"id" => "1"}, {"id" => "2"}], read("id\n\n1\n\n2\n\n")
  end

  def test_a_header_row_only_and_an_empty_document_yield_nothing
    assert_empty read("id,title\n")
    assert_empty read("")
  end

  def test_headers_false_yields_arrays
    assert_equal [["1", ""], ["2"]], read("1,\n2\n", headers: false)
  end

  def test_headers_names_the_columns_of_a_file_without_header_row
    assert_equal [{"id" => "1", "title" => "Moby"}, {"id" => "2", "title" => nil}],
                 read("1,Moby\n2\n", headers: ["id", "title"])
  end

  def test_col_sep_and_quote_char
    assert_equal [{"id" => "1", "title" => "a;b"}], read("id;title\n1;'a;b'\n", col_sep: ";", quote_char: "'")
  end

  def test_quoted_line_breaks_and_quotes
    assert_equal [{"id" => "1", "title" => %(a\n"b")}], read(%(id,title\n1,"a\n""b"""\n))
  end

  def test_crlf_line_ends
    assert_equal [{"id" => "1", "title" => "Moby"}], read("id,title\r\n1,Moby\r\n")
  end

  def test_cr_line_ends
    assert_equal [{"id" => "1", "t" => "a"}, {"id" => "2", "t" => "b"}], read("id,t\r1,a\r2,b\r")
  end

  def test_a_quoted_value_longer_than_a_block
    big = "x" * 100_000

    assert_equal [{"id" => "1", "t" => big}, {"id" => "2", "t" => "ok"}], read(%(id,t\n1,"#{big}"\n2,ok\n))
  end

  # Encodings

  def test_the_utf8_bom_is_removed
    assert_equal [{"id" => "1"}], read("\xEF\xBB\xBFid\n1\n")
  end

  def test_windows1252_is_read_as_utf8
    records = read("id;name\n1;M\xFCller\n", col_sep: ";", encoding: "Windows-1252")

    assert_equal [{"id" => "1", "name" => "Müller"}], records
    assert_equal Encoding::UTF_8, records.first["name"].encoding
  end

  def test_excel_unicode_text_is_read_as_utf8
    bytes = "\uFEFFid\tname\n1\tMüller\n".encode(Encoding::UTF_16LE)
    records = read(bytes, col_sep: "\t", encoding: "UTF-16LE")

    assert_equal [{"id" => "1", "name" => "Müller"}], records
    assert_equal [Encoding::UTF_8], records.first.flatten.map(&:encoding).uniq
  end

  def test_utf16be_with_bom
    bytes = "\uFEFFid\n1\n".encode(Encoding::UTF_16BE)

    assert_equal [{"id" => "1"}], read(bytes, encoding: "UTF-16BE")
  end

  def test_utf16_characters_split_between_blocks
    text = +"id\tt\n"
    4000.times { text << "#{it}\t#{"x" * (it % 7)}😀\n" }
    records = read(text.encode(Encoding::UTF_16LE), col_sep: "\t", encoding: "UTF-16LE")

    assert_equal 4000, records.size
    assert_equal({"id" => "3999", "t" => "xx😀"}, records.last)
  end

  # Rows that cannot be read

  def test_wrong_quoting_is_an_invalid_record_and_reading_goes_on
    records = read(%(id,t\n1,"bad"quote\n2,ok\n))
    invalid = records.first

    assert_equal %(1,"bad"quote), invalid.raw
    assert_instance_of CSV::MalformedCSVError, invalid.error
    assert_equal({"id" => "2", "t" => "ok"}, records.last)
  end

  def test_invalid_bytes_are_an_invalid_record
    records = read("id,t\n1,a\xFFb\n2,ok\n")

    assert_equal "1,a\uFFFDb", records.first.raw
    assert_instance_of CSV::InvalidEncodingError, records.first.error
    assert_equal({"id" => "2", "t" => "ok"}, records.last)
  end

  def test_windows1252_read_as_utf8_names_the_encoding
    invalid = read("id\nM\xFCller\n").first

    assert_equal "Invalid byte sequence in UTF-8 in line 2.", invalid.error.message
  end

  def test_a_byte_without_utf8_form_is_an_invalid_record
    records = read("id\n\x81\n2\n", encoding: "Windows-1252")

    assert_instance_of Encoding::UndefinedConversionError, records.first.error
    assert_equal({"id" => "2"}, records.last)
  end

  def test_more_fields_than_columns_is_an_invalid_record
    invalid = read("a,b\n1,2,3\n").first

    assert_equal "1,2,3", invalid.raw
    assert_instance_of Metacrunch::Csv::ParseError, invalid.error
    assert_equal "row has 3 fields, the header 2", invalid.error.message
  end

  def test_an_unclosed_quote_takes_the_rest_of_the_document
    records = read(%(id,t\n1,ok\n2,"open\n3,x\n))

    assert_equal 2, records.size
    assert_equal %(2,"open\n3,x), records.last.raw
  end

  def test_invalid_utf16_stops_the_document
    bytes = "id\n".encode(Encoding::UTF_16LE).b + "\x00\xD8\n\x00".b
    error = assert_raises(Metacrunch::InputError) { read(bytes, encoding: "UTF-16LE") }

    assert_equal "StringIO: the data is not valid UTF-16LE", error.message
  end

  # The header row

  def test_a_column_named_twice_is_an_input_error
    path = file("data.csv", "a,b,a\n1,2,3\n")
    error = assert_raises(Metacrunch::InputError) { Reader.new(path).each.to_a }

    assert_equal %(#{path}: the header row names the column "a" twice), error.message
  end

  def test_an_empty_column_name_is_an_input_error
    path = file("data.csv", "a,b,\n1,2,3\n")
    error = assert_raises(Metacrunch::InputError) { Reader.new(path).each.to_a }

    assert_equal "#{path}: the header row has an empty column name (column 3)", error.message
  end

  def test_an_unreadable_header_row_is_an_input_error
    error = assert_raises(Metacrunch::InputError) { read(%(a,"b"c\n1,2\n)) }

    assert_match(/\AStringIO: the header row cannot be read \(Any value after quoted field/, error.message)
  end

  # Inputs

  def test_gzip_files
    path = file("data.csv.gz", Zlib.gzip("id\n1\n"))

    assert_equal [{"id" => "1"}], Reader.new(path).each.to_a
  end

  def test_every_member_of_a_tar_archive_has_its_own_header_row
    archive = tar("a.csv" => "id\n1\n", "b.csv" => "name\nMoby\n")

    assert_equal [{"id" => "1"}, {"name" => "Moby"}], read(archive)
  end

  def test_dash_is_stdin
    $stdin = StringIO.new("id\n1\n")

    assert_equal [{"id" => "1"}], Reader.new("-").each.to_a
  ensure
    $stdin = STDIN
  end

  def test_an_array_of_targets
    paths = [file("a.csv", "id\n1\n"), file("b.csv", "id\n2\n")]

    assert_equal [{"id" => "1"}, {"id" => "2"}], Reader.new(paths).each.to_a
  end

  def test_progress_is_the_inputs
    reader = Reader.new(file("data.csv", "id\n1\n"))
    reader.each.to_a

    assert_in_delta 1.0, reader.progress
  end

  def test_each_without_a_block_is_an_enumerator
    assert_instance_of Enumerator, Reader.new("data.csv").each
  end

  private

  def file(name, content)
    File.join(@dir, name).tap { File.binwrite(it, content) }
  end

end
```

- [ ] **Step 6: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/reader_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Csv::Reader (NameError)`.

- [ ] **Step 7: Write `lib/metacrunch/csv/errors.rb` and `lib/metacrunch/csv/reader.rb`**

`lib/metacrunch/csv/errors.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Csv
    # A row that has more fields than there are columns; the error of its
    # InvalidRecord.
    class ParseError < Metacrunch::Error; end
  end
end
```

`lib/metacrunch/csv/reader.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Csv
    # A metacrunch source: reads CSV from what Metacrunch::Input reads
    # (paths, "-" for stdin, IOs or an Array of them; gzip and tar are
    # unpacked) and yields a Hash per row (String keys and values, "" for an
    # empty field, nil for a missing one), or an Array with headers: false.
    # A row that cannot be read is yielded as Metacrunch::InvalidRecord.
    class Reader

      def initialize(targets, col_sep: ",", quote_char: '"', encoding: "UTF-8", headers: true)
        @input = Metacrunch::Input.new(targets)
        @encoding = Csv.encoding(col_sep, quote_char, encoding)
        @headers = check_headers(headers)
        # Ruby's csv cannot go on after invalid bytes. Where it can parse the
        # bytes (Csv.bytewise?), the reader checks every value, and a row with
        # invalid bytes becomes an InvalidRecord; other encodings (UTF-16, ...)
        # are parsed in the encoding, and invalid bytes stop the document.
        @bytewise = Csv.bytewise?(@encoding)
        @parse_encoding = @bytewise ? Encoding::BINARY : @encoding
        @options = {col_sep: syntax(col_sep), quote_char: syntax(quote_char), skip_blanks: true}
      end

      # Without a block an Enumerator.
      def each(&)
        return enum_for(:each) unless block_given?

        @input.each_document { |stream, name| read_document(stream, name, &) }
      end

      # The share of the input read so far; see Metacrunch::Input#progress.
      def progress = @input.progress

      private

      def check_headers(headers)
        return headers if [true, false].include?(headers) || names?(headers)

        raise ArgumentError, "headers must be true, false or an Array of unique, non-empty Strings, " \
                             "got #{headers.inspect}"
      end

      def names?(headers)
        headers.is_a?(Array) && !headers.empty? && headers.all? { it.is_a?(String) && !it.empty? } &&
          headers.uniq.size == headers.size
      end

      def syntax(text) = @bytewise ? text.encode(@encoding).b : text.encode(@encoding)

      def read_document(stream, name, &)
        skip_bom(stream)
        csv = ::CSV.new(Lines.new(stream, @parse_encoding), **@options)
        names = @headers == true ? header(csv, name) : @headers
        while (fields = next_fields(csv, name, &))
          next if fields == :invalid

          yield names ? record(fields, names, csv) : fields
        end
      end

      def skip_bom(stream)
        bom = BOMS[@encoding]
        stream.read(bom.bytesize) if bom && stream.peek(bom.bytesize) == bom
      end

      # The column names from the first row; nil for an empty document.
      def header(csv, name)
        fields = next_fields(csv, name) do |invalid|
          raise InputError, "#{name}: the header row cannot be read (#{invalid.error.message})"
        end
        return if fields.nil?

        empty = fields.index(&:empty?)
        raise InputError, "#{name}: the header row has an empty column name (column #{empty + 1})" if empty

        duplicate = fields.find { fields.count(it) > 1 }
        raise InputError, "#{name}: the header row names the column #{duplicate.inspect} twice" if duplicate

        fields
      end

      # The next row's fields in UTF-8, nil at the end, or :invalid after
      # yielding an InvalidRecord for a row that cannot be read.
      def next_fields(csv, name)
        fields = csv.shift
        return if fields.nil?

        fields.map! { value(it, csv) }
      rescue ::CSV::MalformedCSVError, EncodingError => e
        if e.is_a?(::CSV::InvalidEncodingError) && !@bytewise
          raise InputError, "#{name}: the data is not valid #{@encoding}"
        end

        yield invalid(csv.line, e)
        :invalid
      end

      def value(field, csv)
        return +"" if field.nil?
        return field.encode(Encoding::UTF_8) unless @bytewise

        field.force_encoding(@encoding)
        raise ::CSV::InvalidEncodingError.new(@encoding, csv.lineno) unless field.valid_encoding?

        @encoding == Encoding::UTF_8 ? field : field.encode(Encoding::UTF_8)
      end

      def record(fields, names, csv)
        if fields.size > names.size
          return invalid(csv.line, ParseError.new("row has #{fields.size} fields, the header #{names.size}"))
        end

        names.zip(fields).to_h
      end

      def invalid(line, error)
        raw = line.to_s.dup.force_encoding(@encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        Metacrunch::InvalidRecord.new(raw: raw.scrub.chomp, error:)
      end

    end
  end
end
```

In `lib/metacrunch/csv.rb`, the `require_relative` lines become:

```ruby
require_relative "csv/version"
require_relative "csv/errors"
require_relative "csv/columns"
require_relative "csv/lines"
require_relative "csv/reader"
```

- [ ] **Step 8: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/reader_test.rb`
Expected: `36 runs, 0 failures, 0 errors`, no warnings.

- [ ] **Step 9: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `66 runs, 0 failures`; `Line coverage: 173 / 173 (100.00%)`, `Branch coverage: 81 / 81 (100.00%)`; `no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add Csv::Reader, a source on Metacrunch::Input and Ruby's csv

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: metacrunch-csv: `Writer`

**Files:**
- Create: `lib/metacrunch/csv/writer.rb`
- Modify: `lib/metacrunch/csv.rb` (one `require_relative`)
- Test: `test/unit/writer_test.rb`, `test/integration/round_trip_test.rb`

**Interfaces:**
- Consumes: `Csv.encoding`, `Csv::BOMS` (Task 1); `Columns` (Task 2); `Metacrunch::Output#open`, `#write(string)`, `#close` (core); `Helpers#written`, `#write_error`, `#read` (Task 1).
- Produces: `Metacrunch::Csv::Writer.new(target, columns: nil, header: true, col_sep: ",", quote_char: '"', encoding: "UTF-8", bom: false)` with `open(context)`, `write(record, ctx)`, `write_batch(records, ctxs)`, `close`. Task 5 uses it in jobs and an example.

- [ ] **Step 1: Write the failing tests**

`test/unit/writer_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Helpers

  Writer = Metacrunch::Csv::Writer

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Options

  def test_new_touches_no_file
    path = File.join(@dir, "out.csv")
    Writer.new(path)

    refute_path_exists path
  end

  def test_invalid_options_are_argument_errors
    [{columns: "id"}, {header: "yes"}, {bom: nil}, {encoding: "Klingon"}, {quote_char: ","}].each do |options|
      assert_raises(ArgumentError) { Writer.new(StringIO.new, **options) }
    end
  end

  def test_a_bom_needs_a_unicode_encoding
    error = assert_raises(ArgumentError) { Writer.new(StringIO.new, encoding: "Windows-1252", bom: true) }

    assert_equal "bom: true needs UTF-8, UTF-16LE or UTF-16BE, got Windows-1252", error.message
  end

  # Columns and header

  def test_the_first_record_defines_the_columns
    assert_equal "id,title\n1,Moby\n2,\n", written([{"id" => "1", "title" => "Moby"}, {"id" => "2"}])
  end

  def test_columns_select_and_order_the_keys
    assert_equal "title,id\nMoby,1\n", written([{"id" => "1", "year" => "1851", "title" => "Moby"}],
                                               columns: ["title", "id"])
  end

  def test_columns_name_the_header
    assert_equal "ID,Titel\n1,Moby\n", written([{"id" => "1", "title" => "Moby"}],
                                               columns: {"ID" => "id", "Titel" => "title"})
  end

  def test_a_new_key_without_columns_stops_the_run
    error = write_error([{"id" => "1"}, {"id" => "2", "isbn" => "x"}])

    assert_match(/\Arecord at position 2 has the key "isbn", which the first record does not have/, error.message)
  end

  def test_arrays_without_columns_have_no_header
    assert_equal "1,Moby\n", written([["1", "Moby"]])
  end

  def test_arrays_with_columns_have_its_header
    assert_equal "id,title\n1,Moby\n", written([["1", "Moby"]], columns: ["id", "title"])
  end

  def test_header_false_writes_no_header_row
    assert_equal "1\n", written([{"id" => "1"}], header: false)
  end

  def test_an_empty_run_with_columns_writes_the_header
    assert_equal "id,title\n", written([], columns: ["id", "title"])
  end

  def test_an_empty_run_without_columns_writes_nothing
    assert_empty written([])
  end

  # Values

  def test_values_by_type
    assert_equal "s,1,1.5,true,false,,\"\"\n", written([["s", 1, 1.5, true, false, nil, ""]])
  end

  def test_other_values_are_errors
    error = write_error([{"id" => "1", "date" => Time.now}])

    assert_equal 'record at position 1: column "date" is a Time; turn it into a String in a step', error.message
  end

  def test_errors_in_array_records_name_the_column_number
    error = write_error([[1, [2]]])

    assert_equal "record at position 1: column 2 is an Array; turn it into a String in a step", error.message
  end

  def test_invalid_strings_are_errors
    error = write_error([{"t" => "a\xFFb".dup.force_encoding(Encoding::UTF_8)}])

    assert_equal 'record at position 1: column "t" is not valid UTF-8', error.message
  end

  def test_fields_are_quoted_only_where_needed
    assert_equal %(plain,"a,b","say ""hi""","two\nlines"\n), written([["plain", "a,b", %(say "hi"), "two\nlines"]])
  end

  # Encodings and BOM

  def test_windows1252_for_excel
    bytes = written([{"id" => "1", "name" => "Müller"}], col_sep: ";", encoding: "Windows-1252")

    assert_equal "id;name\n1;M\xFCller\n".b, bytes
  end

  def test_a_character_missing_in_the_encoding_is_an_error
    error = write_error([{"name" => "€uro"}], encoding: "ISO-8859-1")

    assert_match(/\Arecord at position 1 has a character ISO-8859-1 cannot represent/, error.message)
  end

  def test_a_header_name_missing_in_the_encoding_is_an_error
    error = write_error([], columns: ["€"], encoding: "ISO-8859-1")

    assert_match(/\Athe header has a character ISO-8859-1 cannot represent/, error.message)
  end

  def test_bom_for_utf8
    assert_equal "\xEF\xBB\xBFid\n1\n".b, written([{"id" => "1"}], bom: true)
  end

  def test_bom_for_utf16le
    bytes = written([], columns: ["id"], encoding: "UTF-16LE", bom: true)

    assert_equal "\uFEFFid\n".encode(Encoding::UTF_16LE).b, bytes
  end

  def test_an_empty_run_with_bom_writes_the_bom_only
    assert_equal "\xEF\xBB\xBF".b, written([], bom: true)
  end

  # Targets and batches

  def test_a_gz_path_is_compressed
    path = File.join(@dir, "out.csv.gz")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write({"id" => "1"}, ctx)
    writer.close

    assert_equal "id\n1\n", Zlib.gunzip(File.binread(path))
  end

  def test_dash_is_stdout
    out, = capture_io do
      writer = Writer.new("-")
      writer.open(nil)
      writer.write({"id" => "1"}, ctx)
      writer.close
    end

    assert_equal "id\n1\n", out
  end

  def test_a_batch_is_written_like_single_records
    io = StringIO.new("".b)
    writer = Writer.new(io)
    writer.open(nil)
    writer.write_batch([{"id" => "1"}, {"id" => "2"}], [ctx(1), ctx(2)])
    writer.close

    assert_equal "id\n1\n2\n", io.string
  end

end
```

`test/integration/round_trip_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# What the writer writes, the reader reads back.
class RoundTripTest < Minitest::Test

  include Helpers

  RECORDS = [
    {"id" => "00123", "title" => %(The "quoted", title), "note" => ""},
    {"id" => "0306406152", "title" => "two\nlines", "note" => " spaces "},
    {"id" => "3", "title" => "Müller; Ærø", "note" => "€"}
  ].freeze

  def test_strings_and_empty_strings_come_back
    assert_equal RECORDS, read(written(RECORDS))
  end

  def test_with_options_for_excel
    options = {col_sep: ";", encoding: "Windows-1252"}

    assert_equal RECORDS, read(written(RECORDS, **options), **options)
  end

  def test_utf16le_with_bom_and_tabs
    bytes = written(RECORDS, col_sep: "\t", encoding: "UTF-16LE", bom: true)

    assert_equal RECORDS, read(bytes, col_sep: "\t", encoding: "UTF-16LE")
  end

  def test_nil_comes_back_as_an_empty_string
    assert_equal [{"id" => "1", "note" => ""}], read(written([{"id" => "1", "note" => nil}]))
  end

end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/writer_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Csv::Writer (NameError)`.

- [ ] **Step 3: Write `lib/metacrunch/csv/writer.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Csv
    # A metacrunch sink: writes records as CSV rows to what
    # Metacrunch::Output takes (a path, .gz compressed, "-" for stdout or an
    # IO). Columns come from columns: or from the first Hash record.
    class Writer

      def initialize(target, columns: nil, header: true, col_sep: ",", quote_char: '"', encoding: "UTF-8",
                     bom: false)
        @output = Metacrunch::Output.new(target)
        @columns = Columns.new(columns)
        @encoding = Csv.encoding(col_sep, quote_char, encoding)
        @header = flag(:header, header)
        @bom = flag(:bom, bom)
        if @bom && !BOMS.key?(@encoding)
          raise ArgumentError, "bom: true needs UTF-8, UTF-16LE or UTF-16BE, got #{@encoding}"
        end

        @buffer = StringIO.new(+"")
        @csv = ::CSV.new(@buffer, col_sep:, quote_char:, row_sep: "\n")
        @header_written = false
      end

      def open(_context)
        @output.open
        @output.write(BOMS[@encoding]) if @bom
        @output.write(encode(header_line, nil)) if @header && @columns.known?
      end

      def write(record, ctx)
        @output.write(encode(line(record, ctx), ctx))
      end

      # Builds the rows of a batch and writes them in one piece.
      def write_batch(records, ctxs)
        @output.write(encode(records.zip(ctxs).map { |record, ctx| line(record, ctx) }.join, ctxs.first))
      end

      def close = @output.close

      private

      def flag(name, value)
        return value if [true, false].include?(value)

        raise ArgumentError, "#{name}: must be true or false, got #{value.inspect}"
      end

      def header_line
        @header_written = true
        generate(@columns.names)
      end

      def line(record, ctx)
        values = @columns.row(record, ctx).dup
        values.each_index { |index| values[index] = field(values[index], index, ctx) }
        return generate(values) unless @header && !@header_written && @columns.known?

        header_line << generate(values)
      end

      # One CSV object writes every row into a buffer that is emptied again.
      def generate(values)
        @csv << values
        line = @buffer.string.dup
        @buffer.truncate(0)
        @buffer.rewind
        line
      end

      def field(value, index, ctx)
        case value
        when String
          return value if value.valid_encoding?

          raise Metacrunch::Error, "#{column(index, ctx)} is not valid #{value.encoding}"
        when nil then nil
        when Integer, Float, true, false then value.to_s
        else
          raise Metacrunch::Error, "#{column(index, ctx)} is #{Columns.described(value)}; turn it into a String in " \
                                   "a step"
        end
      end

      def column(index, ctx)
        names = @columns.names
        "record at position #{ctx.position}: column #{names ? names[index].inspect : index + 1}"
      end

      # Bytes for the output: an IO such as StringIO would otherwise convert
      # text of another encoding back into its own.
      def encode(text, ctx)
        return text if @encoding == Encoding::UTF_8

        text.encode(@encoding).b
      rescue EncodingError => e
        at = ctx ? "record at position #{ctx.position}" : "the header"
        raise Metacrunch::Error, "#{at} has a character #{@encoding} cannot represent (#{e.message})"
      end

    end
  end
end
```

In `lib/metacrunch/csv.rb`, below `require_relative "csv/reader"`, add:

```ruby
require_relative "csv/writer"
```

`lib/metacrunch/csv.rb` is now complete:

```ruby
# frozen_string_literal: true

require "csv"
require "stringio"
require "metacrunch"
require_relative "csv/version"
require_relative "csv/errors"
require_relative "csv/columns"
require_relative "csv/lines"
require_relative "csv/reader"
require_relative "csv/writer"

module Metacrunch
  # CSV for metacrunch: a source (Reader) and a sink (Writer) on Ruby's csv.
  # Records are Hashes with String keys (or Arrays); values stay Strings.
  module Csv

    # The byte order marks the reader removes and the writer can write.
    BOMS = {
      Encoding::UTF_8 => "\xEF\xBB\xBF".b,
      Encoding::UTF_16LE => "\xFF\xFE".b,
      Encoding::UTF_16BE => "\xFE\xFF".b
    }.freeze

    class << self

      # The Encoding named encoding; raises ArgumentError unless col_sep and
      # quote_char are usable with it.
      def encoding(col_sep, quote_char, encoding)
        found = find(encoding)
        unless col_sep.is_a?(String) && !col_sep.empty?
          raise ArgumentError, "col_sep must be a non-empty String, got #{col_sep.inspect}"
        end
        unless quote_char.is_a?(String) && quote_char.length == 1 && quote_char != col_sep
          raise ArgumentError, "quote_char must be one character other than col_sep, got #{quote_char.inspect}"
        end

        [col_sep, quote_char].each { encodable(it, found) }
        found
      end

      # True for UTF-8 and the single-byte encodings (ISO-8859-1,
      # Windows-1252, ...): no byte of a character there looks like ASCII,
      # so Ruby's csv can parse the bytes.
      def bytewise?(encoding)
        return true if encoding == Encoding::UTF_8

        encoding.ascii_compatible? && (0x80..0xFF).all? { [it].pack("C").force_encoding(encoding).valid_encoding? }
      end

      private

      def find(name)
        encoding = begin
          Encoding.find(name)
        rescue ArgumentError, TypeError
          raise ArgumentError, "encoding must be the name of an encoding, got #{name.inspect}"
        end
        return encoding unless encoding.dummy?

        raise ArgumentError, "encoding #{encoding} has no byte order; use UTF-16LE, UTF-16BE or another encoding"
      end

      def encodable(text, encoding)
        text.encode(encoding)
      rescue EncodingError
        raise ArgumentError, "#{text.inspect} cannot be written in #{encoding}"
      end

    end

  end
end
```

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/writer_test.rb` and `bundle exec ruby -w -Itest -Ilib test/integration/round_trip_test.rb`
Expected: `26 runs, 0 failures, 0 errors` and `4 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `96 runs, 0 failures`; `Line coverage: 230 / 230 (100.00%)`, `Branch coverage: 103 / 103 (100.00%)`; `no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add Csv::Writer, a sink on Metacrunch::Output

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: metacrunch-csv: jobs, examples, benchmark and docs

**Files:**
- Create: `examples/csv2jsonl.rb`, `examples/books2excel.rb`, `examples/data/books.csv`, `bench/csv.rb`, `Readme.md`, `CHANGELOG.md`
- Test: `test/integration/jobs_test.rb`, `test/integration/examples_test.rb`

**Interfaces:**
- Consumes: `Csv::Reader` (Task 3), `Csv::Writer` (Task 4); `Metacrunch.job`, `Job#run(workers:, logger:)` (status `:ok`, `:ok_with_failures`, `:aborted`), `Metacrunch::Testing.run(job)` (`records`, `failures` as `[record, Failure(error, step)]` pairs) and the `metacrunch` executable (core).

- [ ] **Step 1: Write the job tests**

`test/integration/jobs_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class JobsTest < Minitest::Test

  Csv = Metacrunch::Csv

  def setup
    @dir = Dir.mktmpdir
    @input = File.join(@dir, "in.csv")
    File.write(@input, "id,title,year\n1,Moby,1851\n2,\"Emma\",1815\n3,\"bad\"quote,1900\n")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_csv_to_csv_with_and_without_workers
    outputs = [nil, 2].map do |workers|
      output = File.join(@dir, "out-#{workers}.csv")
      result = copy_job(output).run(workers:, logger: Logger.new(nil))

      assert_equal :ok_with_failures, result.status
      File.read(output)
    end

    assert_equal ["year,title\n1851,MOBY\n1815,EMMA\n"], outputs.uniq
  end

  def test_an_unreadable_row_fails_alone
    input = @input
    job = Metacrunch.job do
      source Csv::Reader.new(input)
      on_failure :skip
    end
    result = Metacrunch::Testing.run(job)

    assert_equal 2, result.records.size
    assert_equal(["source"], result.failures.map { it.last.step })
    assert_instance_of CSV::MalformedCSVError, result.failures.first.last.error
  end

  def test_a_value_the_writer_refuses_aborts_the_run
    output = File.join(@dir, "out.csv")
    input = @input
    job = Metacrunch.job do
      source Csv::Reader.new(input)
      on_failure :skip
      map { it["id"] == "2" ? it.merge("year" => Time.now) : it }
      sink Csv::Writer.new(output)
    end
    result = job.run(logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_equal "id,title,year\n1,Moby,1851\n", File.read(output)
  end

  private

  def copy_job(output)
    input = @input
    Metacrunch.job do
      source Csv::Reader.new(input)
      on_failure :skip
      map { it.merge("title" => it["title"].upcase) }
      sink Csv::Writer.new(output, columns: ["year", "title"])
    end
  end

end
```

- [ ] **Step 2: Run them**

Run: `bundle exec ruby -w -Itest -Ilib test/integration/jobs_test.rb`
Expected: `3 runs, 0 failures, 0 errors`. These check finished parts together in the engine (workers, failure policy, an aborted run), so they pass at once; a failure here is a finding about Tasks 3 and 4.

- [ ] **Step 3: Write the failing example test**

`test/integration/examples_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# Runs every example as a user would, through metacrunch's executable.
class ExamplesTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def test_csv2jsonl
    stdout, stderr, status = metacrunch("run", example("csv2jsonl.rb"), example("data/books.csv"))
    records = stdout.lines.map { JSON.parse(it) }

    assert_predicate status, :success?, stderr
    assert_equal([2004, 2019, nil, 1998], records.map { it["year"] })
    assert_equal(["0838908829", "", "0306406152", ""], records.map { it["isbn"] })
  end

  def test_books2excel
    Dir.mktmpdir do |dir|
      output = File.join(dir, "books.csv")
      _stdout, stderr, status = metacrunch("run", example("books2excel.rb"), "--target", output,
                                           example("data/books.csv"))

      lines = File.binread(output).lines

      assert_predicate status, :success?, stderr
      assert_equal ["Nr.;Titel;Jahr\n", "4;M\xFCller's guide to indexing;1998\n".b], lines.values_at(0, 4)
    end
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, *)

end
```

Run: `bundle exec ruby -w -Itest -Ilib test/integration/examples_test.rb`
Expected: 2 failures: the examples do not exist yet, and each failure shows metacrunch's error output.

- [ ] **Step 4: Write the examples**

`examples/csv2jsonl.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch/csv"

# Reads CSV files with a header row and writes one JSON object per row to
# stdout as JSON Lines. Values stay Strings ("0306406152" keeps its zero);
# only the year becomes a number.
#
#   bundle exec metacrunch run examples/csv2jsonl.rb examples/data/books.csv
Metacrunch.job do
  params do
    args :files, min: 1
  end

  source Metacrunch::Csv::Reader.new(params.files), id: ->(record) { record["id"] }

  map do |record|
    record.merge("year" => Integer(record["year"], exception: false))
  end
end
```

`examples/books2excel.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch/csv"

# Writes CSV that Excel opens with a double click in a German or French
# locale: semicolons, Windows-1252, German column names.
#
#   bundle exec metacrunch run examples/books2excel.rb --target tmp/books.csv examples/data/books.csv
#
# The parameter is not called output: metacrunch's own -o/--output, given
# before the job file, would replace the CSV sink with JSON Lines.
Metacrunch.job do
  params do
    param :target, String, default: "-", desc: "CSV file for Excel (- for stdout)"
    args :files, min: 1
  end

  source Metacrunch::Csv::Reader.new(params.files)

  sink Metacrunch::Csv::Writer.new(params.target, columns: {"Nr." => "id", "Titel" => "title", "Jahr" => "year"},
                                                  col_sep: ";", encoding: "Windows-1252")
end
```

`examples/data/books.csv`:

```
id,title,year,isbn
1,Metadata in practice,2004,0838908829
2,"Cataloging, step by step",2019,
3,"The ""quoted"" title",,0306406152
4,Müller's guide to indexing,1998,
```

Run: `bundle exec ruby -w -Itest -Ilib test/integration/examples_test.rb`
Expected: `2 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Write and run the benchmark**

`bench/csv.rb`:

```ruby
# frozen_string_literal: true

# Reads and writes 1 million CSV rows with metacrunch-csv and with Ruby's csv
# and fails when metacrunch-csv takes more than 1.3 times as long.
#
#   bundle exec ruby --yjit bench/csv.rb [rows]
require "logger"
require "tmpdir"
require "metacrunch/csv"

ROWS = Integer(ARGV.fetch(0, 1_000_000))
LIMIT = 1.3

def best_of_three
  Array.new(3) do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end.min
end

# Prints the times; true if metacrunch-csv stays within LIMIT.
def within_limit?(name, ruby, ours)
  ratio = ours / ruby
  puts format("%<name>-5s Ruby's csv %<ruby>.2f s, metacrunch-csv %<ours>.2f s (%<ratio>.2f times)",
              name:, ruby:, ours:, ratio:)
  ratio <= LIMIT
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "data.csv")
  File.open(path, "w") do |file|
    file.puts("id,title,year,isbn")
    ROWS.times { file.puts(%(#{it},"Title, number #{it}",#{1900 + (it % 120)},978316148410#{it % 10})) }
  end

  ruby = best_of_three { CSV.foreach(path, headers: true, &:to_h) }
  ours = best_of_three { Metacrunch::Csv::Reader.new(path).each { nil } }
  read = within_limit?("read", ruby, ours)

  records = Metacrunch::Csv::Reader.new(path).each.to_a
  ctx = Metacrunch::Context.new(id: 1, position: 1, logger: Logger.new(nil))
  output = File.join(dir, "out.csv")
  ruby = best_of_three do
    File.open(output, "w") { |file| records.each { file.write(CSV.generate_line(it.values)) } }
  end
  ours = best_of_three do
    writer = Metacrunch::Csv::Writer.new(output)
    writer.open(nil)
    records.each { writer.write(it, ctx) }
    writer.close
  end

  exit(1) unless [read, within_limit?("write", ruby, ours)].all?
end
```

Run: `bundle exec ruby --yjit bench/csv.rb`
Expected (about a minute): two lines such as `read  Ruby's csv 2.19 s, metacrunch-csv 2.09 s (0.96 times)` and `write Ruby's csv 3.01 s, metacrunch-csv 1.23 s (0.41 times)`, exit status 0. Above 1.3 times, the script exits with 1: stop and find the cause.

- [ ] **Step 6: Write the docs**

`Readme.md`:

````markdown
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
| `quote_char` | `'"'` | one character, not the separator |
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
| bytes that are not valid UTF-8, Windows-1252, ... | `CSV::InvalidEncodingError` |
| a character without a UTF-8 form | `Encoding::UndefinedConversionError` |
| more fields than the header names | `Metacrunch::Csv::ParseError` (`row has 4 fields, the header 3`) |

`raw` is the row as it stands in the file. A quote that is never closed takes the rest of the file into one
`InvalidRecord`. A file in the wrong encoding shows up as many such rows: `Invalid byte sequence in UTF-8 in line 2.`
means that the file needs `encoding:`.

These stop the run with `Metacrunch::InputError`: a header row that names a column twice, has an empty name (`data.csv:
the header row has an empty column name (column 3)`, often from separators at the end of the line; name the columns
with `headers:`, and the header row comes as the first record) or cannot be read; invalid bytes in UTF-16 (`data.csv:
the data is not valid UTF-16LE`), after which Ruby's csv cannot go on; and errors of the input itself (a missing file,
broken gzip).

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
  when the run starts, so an empty run gives a file with the header only.
- Without `columns:`, the first record's keys are the columns; a later record with another key stops the run (name the
  columns with `columns:`). An empty run gives an empty file.
- Array records are written as they are; with `columns:` the header comes from it.

| Value | Field |
|---|---|
| `String` | as it is (`""` is written as `""`) |
| `Integer`, `Float` | `to_s` |
| `true`, `false` | `true`, `false` |
| `nil` | empty |

Anything else (a `Time`, a `Date`, an Array) stops the run: `record at position 7: column "date" is a Time; turn it
into a String in a step`. So do a character the target encoding cannot represent and a String that is not valid in
its encoding. `nil` and `""` are both read back as `""`.

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

## License

MIT; see [License.txt](License.txt).
````

`CHANGELOG.md`:

````markdown
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
  key) or the keys of the first record, `header:`, `col_sep:`, `quote_char:`, `encoding:` and `bom:`.

### Changes from metacrunch-file

- Values stay Strings: `"00123"` is no longer read as `123`. Keys are the column names as Strings, not downcased
  Symbols. Empty fields are `""` instead of being left out.
- The options are the gem's own, not those of smarter_csv.
````

- [ ] **Step 7: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `101 runs, 0 failures`; `Line coverage: 230 / 230 (100.00%)`, `Branch coverage: 103 / 103 (100.00%)`; `23 files inspected, no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add job tests, examples, a benchmark, Readme and CHANGELOG

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: metacrunch-xlsx: the gem and `Columns`

**Files:**
- Create: `metacrunch-xlsx.gemspec`, `Gemfile`, `Rakefile`, `.rubocop.yml`, `.gitignore`, `License.txt`, `.github/workflows/ci.yml`, `lib/metacrunch/xlsx/version.rb`, `lib/metacrunch/xlsx.rb`, `lib/metacrunch/xlsx/columns.rb`
- Test: `test/test_helper.rb`, `test/support/helpers.rb`, `test/unit/columns_test.rb`

**Interfaces:**
- Produces: `Metacrunch::Xlsx::VERSION = "5.0.0.pre"`; `Metacrunch::Xlsx::Columns` with the interface of Task 2 (`new(columns)`, `names`, `known?`, `row(record, ctx)`, `Columns.described(object)`).
- Test helpers (module `Helpers`, they expect `@dir`): `ctx(position = 1)`, `xlsx(records, name: "out.xlsx", **options) -> path`, `write_error(records, **options)`, `rows(path)` (roo; `[]` for an empty sheet), `parts(path)` (name => content in ZIP order), `sheet_xml(path)`, `with_limit(constant_name, value) { }` (lowers `Sheet::MAX_ROWS` or `Sheet::MAX_COLUMNS` while the block runs; Tasks 8 and 9).

- [ ] **Step 1: Create the repository**

```bash
mkdir -p /Users/renspr/Code/Projects/upb/metacrunch/metacrunch-xlsx
git -C /Users/renspr/Code/Projects/upb/metacrunch/metacrunch-xlsx init -b master
```

All later commands of Tasks 6–10 run in `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-xlsx`.

- [ ] **Step 2: Write the gem's files**

`metacrunch-xlsx.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/metacrunch/xlsx/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-xlsx"
  spec.version  = Metacrunch::Xlsx::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "XLSX for metacrunch: a sink that streams Excel files"
  spec.homepage = "https://github.com/ubpb/metacrunch-xlsx"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"
  spec.add_dependency "zip_kit", "~> 6.4"
end
```

`Gemfile`:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# metacrunch 5 is not released yet. METACRUNCH_PATH points to a checkout of
# its metacrunch-ng branch; by default it lies next to this repository.
gem "metacrunch", path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")

group :development do
  gem "minitest", ">= 5.25"
  gem "rake", ">= 13.0"
  # The tests read the written files back.
  gem "rexml", ">= 3.4", require: false
  gem "roo", ">= 3.0", require: false
  gem "rubocop-ubpb", github: "ubpb/rubocop-ubpb", require: false
  gem "rubyzip", ">= 2.4", require: false
  gem "simplecov", ">= 0.22", require: false
end
```

`Rakefile`:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

# Coverage thresholds apply to full runs only (see test/test_helper.rb).
ENV["COVERAGE"] = "1" unless ENV.key?("COVERAGE")

Minitest::TestTask.create do |t|
  t.test_globs = ["test/**/*_test.rb"]
end

RuboCop::RakeTask.new

task default: [:test, :rubocop]
```

`.rubocop.yml`:

```yaml
inherit_gem:
  rubocop-ubpb: ruby.yml

inherit_mode:
  merge:
    - Exclude

Style/FrozenStringLiteralComment:
  Enabled: true

# Tests leave loops on purpose (`each_document { return ... }`).
Lint/UnreachableLoop:
  Exclude:
    - "test/**/*"
```

`.gitignore`:

```
/.bundle/
/coverage/
/pkg/
/tmp/
/vendor/
Gemfile.lock
.DS_Store
```

`License.txt`:

```
Copyright (c) 2026 René Sprotte

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

permissions:
  contents: read

env:
  # metacrunch 5 is not released yet; see the Gemfile.
  METACRUNCH_PATH: vendor/metacrunch

jobs:
  test:
    name: Test (Ruby ${{ matrix.ruby }}, ${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    continue-on-error: ${{ matrix.ruby == 'head' }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        ruby: ["4.0", head]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: ubpb/metacrunch
          ref: metacrunch-ng
          path: vendor/metacrunch
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rake test

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: ubpb/metacrunch
          ref: metacrunch-ng
          path: vendor/metacrunch
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: "4.0"
          bundler-cache: true
      - run: bundle exec rubocop
```

`lib/metacrunch/xlsx/version.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Xlsx

    VERSION = "5.0.0.pre"

  end
end
```

- [ ] **Step 3: Install the bundle**

Run: `bundle install`
Expected: `Bundle complete!` (roo brings nokogiri and rubyzip).

- [ ] **Step 4: Write the failing test**

`test/test_helper.rb`:

```ruby
# frozen_string_literal: true

if ENV.key?("COVERAGE")
  require "simplecov"

  SimpleCov.start do
    # One run is one result: no merging with results of earlier runs.
    merging false
    enable_coverage :branch
    minimum_coverage line: 95, branch: 90
    skip "/test/"
    skip "/vendor/"
  end
end

require "minitest/autorun"
require "logger"
require "stringio"
require "tmpdir"
require "fileutils"
require "rexml/document"
require "zip"
require "metacrunch/xlsx"

# roo requires cgi, which warns on Ruby 4.0.
verbose = $VERBOSE
$VERBOSE = nil
require "roo"
$VERBOSE = verbose

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
```

`test/support/helpers.rb`:

```ruby
# frozen_string_literal: true

# Helpers shared by the tests. They expect @dir, a temporary directory.
module Helpers

  # A context as the engine passes it to a sink.
  def ctx(position = 1) = Metacrunch::Context.new(id: position, position:, logger: Logger.new(nil))

  # Writes records to a file in @dir and returns its path.
  def xlsx(records, name: "out.xlsx", **)
    path = File.join(@dir, name)
    writer = Metacrunch::Xlsx::Writer.new(path, **)
    writer.open(nil)
    records.each_with_index { |record, index| writer.write(record, ctx(index + 1)) }
    writer.close
    path
  end

  # The error the writer raises for records.
  def write_error(records, **) = assert_raises(Metacrunch::Error) { xlsx(records, name: "error.xlsx", **) }

  # The rows of the worksheet as roo reads them; [] for an empty sheet.
  def rows(path)
    sheet = Roo::Excelx.new(path).sheet(0)
    sheet.first_row ? sheet.to_a : []
  end

  # name => content of the parts, in the order of the ZIP container.
  def parts(path)
    Zip::File.open(path) { |zip| zip.entries.to_h { [it.name, it.get_input_stream.read] } }
  end

  # The XML of the worksheet.
  def sheet_xml(path) = parts(path).fetch("xl/worksheets/sheet1.xml")

  # Replaces a constant of Metacrunch::Xlsx::Sheet while the block runs.
  def with_limit(name, value)
    sheet = Metacrunch::Xlsx::Sheet
    original = sheet.const_get(name)
    sheet.send(:remove_const, name)
    sheet.const_set(name, value)
    yield
  ensure
    sheet.send(:remove_const, name)
    sheet.const_set(name, original)
  end

end
```

`test/unit/columns_test.rb` (metacrunch-csv's with the constant and the comment changed):

```ruby
# frozen_string_literal: true

require "test_helper"

# The same tests as in metacrunch-csv; only this constant differs.
class ColumnsTest < Minitest::Test

  Columns = Metacrunch::Xlsx::Columns

  include Helpers

  def test_without_columns_nothing_is_known
    columns = Columns.new(nil)

    refute_predicate columns, :known?
    assert_nil columns.names
  end

  def test_an_array_names_the_keys_and_the_header
    columns = Columns.new(["id", "title"])

    assert_equal ["id", "title"], columns.names
    assert_equal ["2", "Moby"], columns.row({"title" => "Moby", "id" => "2", "year" => "1851"}, ctx)
  end

  def test_a_hash_maps_header_names_to_keys
    columns = Columns.new({"ID" => "id", "Titel" => "title"})

    assert_equal ["ID", "Titel"], columns.names
    assert_equal ["2", "Moby"], columns.row({"title" => "Moby", "id" => "2"}, ctx)
  end

  def test_missing_keys_are_nil
    assert_equal ["2", nil], Columns.new(["id", "title"]).row({"id" => "2"}, ctx)
  end

  def test_invalid_columns_are_argument_errors
    [:id, "id", [], ["a", "a"], ["", "b"], [1], {"A" => 1}, {"A" => ""}, {a: "a"}].each do |columns|
      assert_raises(ArgumentError) { Columns.new(columns) }
    end
  end

  def test_a_named_column_twice_names_it
    error = assert_raises(ArgumentError) { Columns.new(["a", "b", "a"]) }

    assert_equal 'the column "a" is named twice', error.message
  end

  def test_the_first_record_defines_the_columns
    columns = Columns.new(nil)
    columns.row({"id" => "1", "title" => "Moby"}, ctx)

    assert_equal ["id", "title"], columns.names
    assert_equal ["2", nil], columns.row({"id" => "2"}, ctx(2))
  end

  def test_symbol_keys_give_string_names
    columns = Columns.new(nil)

    assert_equal ["1"], columns.row({id: "1"}, ctx)
    assert_equal ["id"], columns.names
  end

  def test_a_new_key_without_columns_stops_the_run
    columns = Columns.new(nil)
    columns.row({"id" => "1"}, ctx)
    error = assert_raises(Metacrunch::Error) { columns.row({"id" => "7", "isbn" => "x"}, ctx(7)) }

    assert_equal 'record at position 7 has the key "isbn", which the first record does not have; ' \
                 "name the columns with columns:", error.message
  end

  def test_with_columns_other_keys_are_ignored
    assert_equal ["1"], Columns.new(["id"]).row({"id" => "1", "isbn" => "x"}, ctx)
  end

  def test_arrays_are_rows_as_they_are
    columns = Columns.new(nil)

    assert_equal ["1", 2], columns.row(["1", 2], ctx)
    refute_predicate columns, :known?
  end

  def test_an_array_longer_than_the_columns_is_an_error
    error = assert_raises(Metacrunch::Error) { Columns.new(["a", "b"]).row([1, 2, 3], ctx(4)) }

    assert_equal "record at position 4 has 3 values for 2 columns", error.message
  end

  def test_hashes_and_arrays_do_not_mix
    columns = Columns.new(nil)
    columns.row({"a" => 1}, ctx)
    error = assert_raises(Metacrunch::Error) { columns.row([1], ctx(2)) }

    assert_equal "record at position 2 is an Array, the records before it are Hashes; write either Hashes or Arrays",
                 error.message
  end

  def test_arrays_and_hashes_do_not_mix
    columns = Columns.new(nil)
    columns.row([1], ctx)
    error = assert_raises(Metacrunch::Error) { columns.row({"a" => 1}, ctx(2)) }

    assert_match(/is a Hash, the records before it are Arrays/, error.message)
  end

  def test_other_records_are_errors
    error = assert_raises(Metacrunch::Error) { Columns.new(nil).row("1,2", ctx(3)) }

    assert_equal "record at position 3 is a String, not a Hash or an Array", error.message
  end

end
```

- [ ] **Step 5: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/columns_test.rb`
Expected: `cannot load such file -- metacrunch/xlsx (LoadError)`.

- [ ] **Step 6: Write `lib/metacrunch/xlsx.rb` and `lib/metacrunch/xlsx/columns.rb`**

`lib/metacrunch/xlsx.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch"
require "zip_kit"
require_relative "xlsx/version"
require_relative "xlsx/columns"

module Metacrunch
  # XLSX for metacrunch: a sink (Writer) that streams one worksheet.
  module Xlsx
  end
end
```

`lib/metacrunch/xlsx/columns.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # Turns records into rows: the columns: of a writer, or the keys of the
    # first Hash record. The same rules hold in metacrunch-csv.
    class Columns

      PLURALS = {Hash => "Hashes", Array => "Arrays"}.freeze

      # "a Time", "an Array": the class of object with its article.
      def self.described(object)
        name = object.class.name
        "#{name.match?(/\A[AEIOU]/) ? "an" : "a"} #{name}"
      end

      # columns: nil, an Array of unique, non-empty Strings (keys, also the
      # header), or a Hash of header => key.
      def initialize(columns)
        @names, @keys = parse(columns)
        @given = !@keys.nil?
        @kind = nil
      end

      # The header names, or nil while they are not known.
      attr_reader :names

      def known? = !@names.nil?

      # The values of record in column order. Learns the columns from the
      # first Hash record when none were given.
      def row(record, ctx)
        kind = record_kind(record, ctx)
        kind == Hash ? hash_row(record, ctx) : array_row(record, ctx)
      end

      private

      def parse(columns)
        case columns
        when nil then [nil, nil]
        when Array then [check_names(columns), columns]
        when Hash then [check_names(columns.keys), check_keys(columns.values)]
        else raise ArgumentError, "columns must be nil, an Array or a Hash, got #{columns.inspect}"
        end
      end

      def check_names(names)
        unless names.all? { it.is_a?(String) && !it.empty? }
          raise ArgumentError, "column names must be non-empty Strings, got #{names.inspect}"
        end
        raise ArgumentError, "columns must not be empty" if names.empty?

        duplicate = names.find { names.count(it) > 1 }
        raise ArgumentError, "the column #{duplicate.inspect} is named twice" if duplicate

        names
      end

      def check_keys(keys)
        return keys if keys.all? { it.is_a?(String) && !it.empty? }

        raise ArgumentError, "column keys must be non-empty Strings, got #{keys.inspect}"
      end

      # Hash or Array; the first record decides for the run.
      def record_kind(record, ctx)
        kind = [Hash, Array].find { record.is_a?(it) }
        unless kind
          raise Metacrunch::Error, "record at position #{ctx.position} is #{Columns.described(record)}, " \
                                   "not a Hash or an Array"
        end
        @kind ||= kind
        return kind if kind == @kind

        raise Metacrunch::Error, "record at position #{ctx.position} is #{Columns.described(record)}, the records " \
                                 "before it are #{PLURALS[@kind]}; write either Hashes or Arrays"
      end

      def hash_row(record, ctx)
        unless @keys
          @keys = record.keys
          @names = @keys.map(&:to_s)
        end
        check_new_keys(record, ctx) unless @given
        @keys.map { record[it] }
      end

      def check_new_keys(record, ctx)
        return if record.size <= @keys.size && record.each_key.all? { @keys.include?(it) }

        key = record.each_key.find { !@keys.include?(it) }
        raise Metacrunch::Error, "record at position #{ctx.position} has the key #{key.inspect}, which the first " \
                                 "record does not have; name the columns with columns:"
      end

      def array_row(record, ctx)
        return record unless @keys && record.size > @keys.size

        raise Metacrunch::Error, "record at position #{ctx.position} has #{record.size} values for " \
                                 "#{@keys.size} columns"
      end

    end
  end
end
```

Check that the two copies differ only in the namespace and the comment:

Run: `diff ../metacrunch-csv/lib/metacrunch/csv/columns.rb lib/metacrunch/xlsx/columns.rb` and `diff ../metacrunch-csv/test/unit/columns_test.rb test/unit/columns_test.rb`
Expected: only lines 4 and 6 (`module Csv`/`module Xlsx`, the comment) and lines 5 and 8 (the comment, the constant).

- [ ] **Step 7: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/columns_test.rb`
Expected: `15 runs, 0 failures, 0 errors`, no warnings.

- [ ] **Step 8: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `15 runs, 0 failures`; `Line coverage: 59 / 59 (100.00%)`, `Branch coverage: 28 / 28 (100.00%)`; `no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Set up metacrunch-xlsx with the column model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: metacrunch-xlsx: `Cells`

**Files:**
- Create: `lib/metacrunch/xlsx/cells.rb`
- Modify: `lib/metacrunch/xlsx.rb` (one `require_relative`)
- Test: `test/unit/cells_test.rb`

**Interfaces:**
- Consumes: `Columns.described` (Task 6).
- Produces: `Metacrunch::Xlsx::Cells` (module functions): `column(index) -> "A"…"XFD"`; `cell(value, ref, style = nil) -> String or nil`; `text_element(string) -> "<t>…</t>"`; `escape(text)`; constants `MAX_DIGITS = 15`, `MAX_TEXT = 32_767`; `Cells::Unwritable < StandardError` with `#index` (the column's index, or nil for the whole row) and `Unwritable.new(message, index: nil)`. Tasks 8 and 9 use these.

- [ ] **Step 1: Write the failing test**

`test/unit/cells_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CellsTest < Minitest::Test

  Cells = Metacrunch::Xlsx::Cells

  def test_column_letters
    assert_equal(["A", "Z", "AA", "AZ", "ZZ", "AAA", "XFD"], [0, 25, 26, 51, 701, 702, 16_383].map { Cells.column(it) })
  end

  def test_nil_is_no_cell
    assert_nil Cells.cell(nil, "A1")
  end

  def test_strings_are_inline_text
    assert_equal '<c r="A1" t="inlineStr"><is><t>00123</t></is></c>', Cells.cell("00123", "A1")
  end

  def test_text_is_escaped
    assert_equal "<t>a &lt;b&gt; &amp; &quot;c&quot;</t>", Cells.text_element(%(a <b> & "c"))
  end

  def test_spaces_at_the_ends_are_preserved
    assert_equal '<t xml:space="preserve"> a </t>', Cells.text_element(" a ")
  end

  def test_character_codes_are_escaped
    assert_equal "<t>_x005F_x0041_ and _x005F_x00e9_</t>", Cells.text_element("_x0041_ and _x00e9_")
  end

  def test_text_in_another_encoding_is_written_as_utf8
    assert_equal "<t>Müller</t>", Cells.text_element("Müller".encode(Encoding::ISO_8859_1))
  end

  def test_integers_and_floats_are_numbers
    assert_equal '<c r="B2"><v>-42</v></c>', Cells.cell(-42, "B2")
    assert_equal '<c r="B2"><v>1.5</v></c>', Cells.cell(1.5, "B2")
  end

  def test_fifteen_digits_are_a_number
    assert_equal '<c r="A1"><v>999999999999999</v></c>', Cells.cell(999_999_999_999_999, "A1")
  end

  def test_booleans
    assert_equal '<c r="A1" t="b"><v>1</v></c>', Cells.cell(true, "A1")
    assert_equal '<c r="A1" t="b"><v>0</v></c>', Cells.cell(false, "A1")
  end

  def test_a_style_is_an_attribute
    assert_equal '<c r="A1" s="1" t="inlineStr"><is><t>id</t></is></c>', Cells.cell("id", "A1", 1)
  end

  def test_unwritable_values
    {
      10**15 => "has more than 15 digits, which Excel cannot keep; turn it into a String in a step",
      Float::NAN => "is NaN, which Excel cannot store",
      -Float::INFINITY => "is -Infinity, which Excel cannot store",
      Time.at(0) => "is a Time; turn it into a String or a number in a step",
      ["a"] => "is an Array; turn it into a String or a number in a step"
    }.each do |value, message|
      assert_equal message, assert_raises(Cells::Unwritable) { Cells.cell(value, "A1") }.message
    end
  end

  def test_unwritable_text
    {
      "a\u0001" => "has a character that XML does not allow",
      "a" * 32_768 => "has more than 32767 characters",
      "a\xFF".dup.force_encoding(Encoding::UTF_8) => "is not valid UTF-8",
      "a\xFF".b => "has no UTF-8 form (it is ASCII-8BIT)"
    }.each do |value, message|
      assert_equal message, assert_raises(Cells::Unwritable) { Cells.cell(value, "A1") }.message
    end
  end

  def test_the_longest_text_and_tabs_and_line_breaks_are_written
    assert_equal 32_767, Cells.text_element("a" * 32_767).count("a")
    assert_equal "<t>a\tb\r\nc</t>", Cells.text_element("a\tb\r\nc")
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/cells_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Xlsx::Cells (NameError)`.

- [ ] **Step 3: Write `lib/metacrunch/xlsx/cells.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The XML of cells, by the Ruby type of their values. Internal.
    module Cells

      # Excel keeps 15 significant digits; it would change longer Integers.
      MAX_DIGITS = 15
      MAX_TEXT = 32_767
      # Characters XML 1.0 does not allow (tab, LF and CR are allowed).
      INVALID_XML = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/
      # Text Excel would read as a character code (_x0041_ for "A").
      CHARACTER_CODE = /_(x[0-9A-Fa-f]{4}_)/
      ESCAPES = {"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;"}.freeze

      # A value or row that cannot be written; index: the column's index, or
      # nil for the whole row. Writer adds the record's position.
      class Unwritable < StandardError

        attr_reader :index

        def initialize(message, index: nil)
          @index = index
          super(message)
        end

      end

      module_function

      # The letters of the column at index (0-based): A, ..., Z, AA, ...
      def column(index)
        name = +""
        number = index + 1
        while number.positive?
          number, rest = (number - 1).divmod(26)
          name.prepend((65 + rest).chr)
        end
        name
      end

      # The XML of a cell at ref, or nil for nil. style: the index of a cell
      # format (1 is bold) or nil.
      def cell(value, ref, style = nil)
        case value
        when nil then nil
        when String then text(value, ref, style)
        when true, false then %(<c r="#{ref}"#{style_attribute(style)} t="b"><v>#{value ? 1 : 0}</v></c>)
        when Integer then number(integer(value), ref, style)
        when Float then number(float(value), ref, style)
        else raise Unwritable, "is #{Columns.described(value)}; turn it into a String or a number in a step"
        end
      end

      def text(value, ref, style)
        %(<c r="#{ref}"#{style_attribute(style)} t="inlineStr"><is>#{text_element(value)}</is></c>)
      end

      def text_element(value)
        text = utf8(value)
        raise Unwritable, "has more than #{MAX_TEXT} characters" if text.length > MAX_TEXT
        raise Unwritable, "has a character that XML does not allow" if text.match?(INVALID_XML)

        preserve = text.match?(/\A\s|\s\z/) ? ' xml:space="preserve"' : ""
        "<t#{preserve}>#{escape(text.gsub(CHARACTER_CODE, "_x005F_\\1"))}</t>"
      end

      def utf8(value)
        raise Unwritable, "is not valid #{value.encoding}" unless value.valid_encoding?
        return value if value.encoding == Encoding::UTF_8

        value.encode(Encoding::UTF_8)
      rescue EncodingError
        raise Unwritable, "has no UTF-8 form (it is #{value.encoding})"
      end

      def escape(text) = text.gsub(/[&<>"]/, ESCAPES)

      def integer(value)
        return value.to_s if value.abs < 10**MAX_DIGITS

        raise Unwritable, "has more than #{MAX_DIGITS} digits, which Excel cannot keep; turn it into a String in a step"
      end

      def float(value)
        return value.to_s if value.finite?

        raise Unwritable, "is #{value}, which Excel cannot store"
      end

      def number(text, ref, style) = %(<c r="#{ref}"#{style_attribute(style)}><v>#{text}</v></c>)

      def style_attribute(style) = style ? %( s="#{style}") : ""

    end
  end
end
```

In `lib/metacrunch/xlsx.rb`, below `require_relative "xlsx/columns"`, add:

```ruby
require_relative "xlsx/cells"
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/cells_test.rb`
Expected: `14 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `29 runs, 0 failures`; `Line coverage: 111 / 111 (100.00%)`; `no offenses detected`.

Run the invisible-character check (`cells.rb` holds `\u` escapes in `INVALID_XML`), then:

```bash
git add -A
git commit -m "Add Cells, the XML of a cell by the Ruby type of its value

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: metacrunch-xlsx: `Sheet` and `Package`

**Files:**
- Create: `lib/metacrunch/xlsx/sheet.rb`, `lib/metacrunch/xlsx/package.rb`
- Modify: `lib/metacrunch/xlsx.rb` (two `require_relative`)
- Test: `test/unit/sheet_test.rb`, `test/unit/package_test.rb`

**Interfaces:**
- Consumes: `Cells.cell`, `Cells.column`, `Cells.escape`, `Cells::Unwritable` (Task 7); `Helpers#with_limit` (Task 6).
- Produces: `Metacrunch::Xlsx::Sheet.new(sink)` (sink: anything with `<<`) with `start(header_or_nil, widths_or_nil)`, `started?`, `row(values)`, `finish`, `range`, `absolute_range`, `rows`, `columns`; constants `MAX_ROWS = 1_048_576`, `MAX_COLUMNS = 16_384`, `BOLD = 1`, `HEAD`, `FROZEN`. `Metacrunch::Xlsx::Package::STATIC` (part name => XML, in the order to write) and `Package.workbook(sheet_name, absolute_range_or_nil)`. Task 9 uses both.

- [ ] **Step 1: Write the failing test for `Sheet`**

`test/unit/sheet_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class SheetTest < Minitest::Test

  include Helpers

  Sheet = Metacrunch::Xlsx::Sheet

  def setup
    @xml = +""
    @sheet = Sheet.new(@xml)
  end

  def test_a_header_is_bold_and_frozen
    @sheet.start(["id", "title"], nil)

    assert_includes @xml, '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
    assert_includes @xml, '<sheetData><row r="1"><c r="A1" s="1" t="inlineStr"><is><t>id</t></is></c>'
    assert_equal 1, @sheet.rows
  end

  def test_without_header_no_pane
    @sheet.start(nil, nil)

    assert_equal "#{Sheet::HEAD}<sheetData>", @xml
    assert_predicate @sheet, :started?
  end

  def test_an_empty_header_is_no_header
    @sheet.start([], nil)

    refute_includes @xml, "<pane"
    assert_equal 0, @sheet.rows
  end

  def test_widths_come_before_the_rows
    @sheet.start(["id", "title"], [nil, 60])

    assert_includes @xml, '<cols><col min="2" max="2" width="60" customWidth="1"/></cols><sheetData>'
  end

  def test_rows_are_numbered
    @sheet.start(["id"], nil)
    @sheet.row(["1"])
    @sheet.row([nil, 2])

    assert_includes @xml, '<row r="3"><c r="B3"><v>2</v></c></row>'
  end

  def test_a_row_that_cannot_be_written_writes_nothing
    @sheet.start(nil, nil)
    error = assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.row(["a", Time.at(0)]) }

    assert_equal 1, error.index
    assert_equal ["#{Sheet::HEAD}<sheetData>", 0], [@xml, @sheet.rows]
  end

  def test_a_header_that_cannot_be_written_writes_nothing
    assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.start(["a\u0001"], nil) }
    assert_empty @xml
    refute_predicate @sheet, :started?
  end

  def test_the_autofilter_covers_the_header_and_all_rows
    @sheet.start(["id", "title"], nil)
    2.times { @sheet.row(["1", "x", "wide"]) }
    @sheet.finish

    assert @xml.end_with?('</sheetData><autoFilter ref="A1:C3"/></worksheet>')
    assert_equal "$A$1:$C$3", @sheet.absolute_range
  end

  def test_without_header_no_autofilter
    @sheet.start(nil, nil)
    @sheet.row(["1"])
    @sheet.finish

    assert @xml.end_with?("</row></sheetData></worksheet>")
    assert_nil @sheet.absolute_range
  end

  def test_the_row_limit
    with_limit(:MAX_ROWS, 2) do
      @sheet.start(["id"], nil)
      @sheet.row(["1"])
      error = assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.row(["2"]) }

      assert_equal "would be row 3; Excel has 2 rows", error.message
    end
  end

  def test_the_column_limit
    with_limit(:MAX_COLUMNS, 2) do
      @sheet.start(nil, nil)
      error = assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.row([1, 2, 3]) }

      assert_equal "has 3 values; Excel has 2 columns", error.message
      assert_nil error.index
    end
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/sheet_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Xlsx::Sheet (NameError)`.

- [ ] **Step 3: Write `lib/metacrunch/xlsx/sheet.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The worksheet's XML, written row by row to a sink (a ZIP entry). The
    # start waits for the columns, since column widths come before the rows.
    # Internal.
    class Sheet

      MAX_ROWS = 1_048_576
      MAX_COLUMNS = 16_384
      BOLD = 1
      HEAD = <<~XML.delete("\n").freeze
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
         xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      XML
      FROZEN = '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" ' \
               'state="frozen"/></sheetView></sheetViews>'

      # The rows so far, the header included, and the most values in a row.
      attr_reader :rows, :columns

      def initialize(sink)
        @sink = sink
        @rows = 0
        @columns = 0
        @header = false
        @started = false
      end

      def started? = @started

      # Writes the start of the worksheet. header: the names of a header row,
      # or nil. widths: widths by position (nil for Excel's default), or nil.
      # Raises Cells::Unwritable for a header that cannot be written, and
      # then writes nothing.
      def start(header, widths)
        header = nil if header && header.empty?
        first = header && row_xml(header, 1, BOLD)
        xml = +HEAD
        xml << FROZEN if header
        xml << cols(widths) if widths&.any?
        xml << "<sheetData>"
        xml << first if first
        @sink << xml
        @started = true
        count(header) if header
        @header = !header.nil?
      end

      # Writes a row of values. Raises Cells::Unwritable (with the column's
      # index for a value) for a row that cannot be written, and then writes
      # nothing.
      def row(values)
        @sink << row_xml(values, @rows + 1, nil)
        count(values)
      end

      # Ends the worksheet: the autofilter covers the header and all rows.
      def finish
        filter = %(<autoFilter ref="#{range}"/>) if @header
        @sink << "</sheetData>#{filter}</worksheet>"
      end

      # The range of the header and all rows ("A1:C10"); nil without a
      # header.
      def range
        return unless @header

        "A1:#{Cells.column(@columns - 1)}#{@rows}"
      end

      # The range in Excel's absolute form ("$A$1:$C$10").
      def absolute_range = range&.gsub(/([A-Z]+)(\d+)/, '$\1$\2')

      private

      def count(values)
        @rows += 1
        @columns = values.size if values.size > @columns
      end

      def cols(widths)
        entries = widths.each_with_index.filter_map do |width, index|
          %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>) if width
        end
        "<cols>#{entries.join}</cols>"
      end

      def row_xml(values, number, style)
        raise Cells::Unwritable, "would be row #{number}; Excel has #{MAX_ROWS} rows" if number > MAX_ROWS
        if values.size > MAX_COLUMNS
          raise Cells::Unwritable, "has #{values.size} values; Excel has #{MAX_COLUMNS} columns"
        end

        xml = %(<row r="#{number}">)
        values.each_with_index do |value, index|
          cell = Cells.cell(value, "#{Cells.column(index)}#{number}", style)
          xml << cell if cell
        rescue Cells::Unwritable => e
          raise Cells::Unwritable.new(e.message, index:)
        end
        xml << "</row>"
      end

    end
  end
end
```

In `lib/metacrunch/xlsx.rb`, below `require_relative "xlsx/cells"`, add:

```ruby
require_relative "xlsx/sheet"
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/sheet_test.rb`
Expected: `11 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Write the failing test for `Package`**

`test/unit/package_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class PackageTest < Minitest::Test

  Package = Metacrunch::Xlsx::Package

  def test_the_static_parts
    assert_equal ["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/styles.xml"],
                 Package::STATIC.keys
  end

  def test_the_static_parts_are_xml
    Package::STATIC.each_value { |xml| assert_instance_of REXML::Document, REXML::Document.new(xml) }
  end

  def test_the_second_cell_format_is_bold
    styles = REXML::Document.new(Package::STATIC.fetch("xl/styles.xml"))
    font = REXML::XPath.first(styles, "//cellXfs/xf[2]/@fontId").value

    assert_equal ["b"], REXML::XPath.match(styles, "//fonts/font[#{Integer(font) + 1}]/b").map(&:name)
  end

  def test_the_workbook_names_the_autofilter
    xml = Package.workbook("Books", "$A$1:$C$3")

    assert_includes xml, '<sheet name="Books" sheetId="1" r:id="rId1"/>'
    assert_includes xml, %(<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'Books'!$A$1:$C$3<)
  end

  def test_quotes_and_ampersands_in_the_sheet_name
    xml = REXML::Document.new(Package.workbook("Tom's & Jerry's", "$A$1:$A$1"))

    assert_equal "Tom's & Jerry's", REXML::XPath.first(xml, "//sheet/@name").value
    assert_equal "'Tom''s & Jerry''s'!$A$1:$A$1", REXML::XPath.first(xml, "//definedName").text
  end

  def test_without_autofilter_no_defined_names
    refute_includes Package.workbook("Books", nil), "definedNames"
  end

end
```

Run: `bundle exec ruby -w -Itest -Ilib test/unit/package_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Xlsx::Package (NameError)`.

- [ ] **Step 6: Write `lib/metacrunch/xlsx/package.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The parts of an XLSX file besides the worksheet. Internal.
    module Package

      MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
      RELATIONSHIPS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
      PACKAGE_RELATIONSHIPS = "http://schemas.openxmlformats.org/package/2006/relationships"
      DECLARATION = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n)
      TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml"

      # Written first: content types, relationships and styles.
      STATIC = {
        "[Content_Types].xml" => <<~XML.delete("\n").freeze,
          #{DECLARATION.chomp}
          <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="#{TYPE}.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="#{TYPE}.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="#{TYPE}.styles+xml"/>
          </Types>
        XML
        "_rels/.rels" => <<~XML.delete("\n").freeze,
          #{DECLARATION.chomp}
          <Relationships xmlns="#{PACKAGE_RELATIONSHIPS}">
          <Relationship Id="rId1" Type="#{RELATIONSHIPS}/officeDocument" Target="xl/workbook.xml"/>
          </Relationships>
        XML
        "xl/_rels/workbook.xml.rels" => <<~XML.delete("\n").freeze,
          #{DECLARATION.chomp}
          <Relationships xmlns="#{PACKAGE_RELATIONSHIPS}">
          <Relationship Id="rId1" Type="#{RELATIONSHIPS}/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="#{RELATIONSHIPS}/styles" Target="styles.xml"/>
          </Relationships>
        XML
        "xl/styles.xml" => <<~XML.delete("\n").freeze
          #{DECLARATION.chomp}
          <styleSheet xmlns="#{MAIN}">
          <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>
          <font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
          <fills count="2"><fill><patternFill patternType="none"/></fill>
          <fill><patternFill patternType="gray125"/></fill></fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
          </styleSheet>
        XML
      }.freeze

      module_function

      # The workbook, written last: it names the autofilter's range
      # (absolute, e.g. "$A$1:$C$10") once the last row is known.
      def workbook(sheet, filter)
        root = %(<workbook xmlns="#{MAIN}" xmlns:r="#{RELATIONSHIPS}">)
        sheets = %(<sheets><sheet name="#{Cells.escape(sheet)}" sheetId="1" r:id="rId1"/></sheets>)
        "#{DECLARATION}#{root}#{sheets}#{defined_names(sheet, filter)}</workbook>"
      end

      # The autofilter's range as Excel names it; the sheet's name is quoted,
      # a ' in it doubled.
      def defined_names(sheet, filter)
        return "" unless filter

        name = %(<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">)
        "<definedNames>#{name}#{Cells.escape("'#{sheet.gsub("'", "''")}'!#{filter}")}</definedName></definedNames>"
      end

    end
  end
end
```

In `lib/metacrunch/xlsx.rb`, below `require_relative "xlsx/sheet"`, add:

```ruby
require_relative "xlsx/package"
```

Run: `bundle exec ruby -w -Itest -Ilib test/unit/package_test.rb`
Expected: `6 runs, 0 failures, 0 errors`.

- [ ] **Step 7: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `46 runs, 0 failures`; `Line coverage: 187 / 187 (100.00%)`; `no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add Sheet and Package, the parts of an XLSX file

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: metacrunch-xlsx: `Writer`

**Files:**
- Create: `lib/metacrunch/xlsx/writer.rb`
- Modify: `lib/metacrunch/xlsx.rb` (one `require_relative`)
- Test: `test/unit/writer_test.rb`

**Interfaces:**
- Consumes: `Columns` (Task 6), `Cells::Unwritable` (Task 7), `Sheet`, `Package` (Task 8); `Metacrunch::Output` (core; `ZipKit::Streamer.new(output)` writes to it with `write`); `ZipKit::Streamer#write_deflated_file(name)` (with a block, or without one returning a writable that must be closed before the next entry) and `#close` (writes the central directory).
- Produces: `Metacrunch::Xlsx::Writer.new(target, columns: nil, header: true, sheet: "Sheet1", widths: nil)` with `open(context)`, `write(record, ctx)`, `write_batch(records, ctxs)`, `close`. Task 10 uses it.

- [ ] **Step 1: Write the failing test**

`test/unit/writer_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Helpers

  Writer = Metacrunch::Xlsx::Writer

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Options

  def test_new_touches_no_file
    path = File.join(@dir, "out.xlsx")
    Writer.new(path)

    refute_path_exists path
  end

  def test_invalid_sheet_names
    ["", "a" * 32, "a/b", "a[1]", "a:b", "a*", "a?", "a\\b", "'a", "a'", :Sheet1].each do |sheet|
      assert_raises(ArgumentError) { Writer.new("out.xlsx", sheet:) }
    end
  end

  def test_invalid_widths
    [{"a" => 0}, {"a" => -1}, {"a" => 256}, {"a" => "10"}, [0], "10", 10].each do |widths|
      assert_raises(ArgumentError) { Writer.new("out.xlsx", widths:) }
    end
  end

  def test_invalid_columns_and_header
    assert_raises(ArgumentError) { Writer.new("out.xlsx", columns: "id") }
    assert_raises(ArgumentError) { Writer.new("out.xlsx", header: nil) }
  end

  # Cells and rows

  def test_cells_by_type
    path = xlsx([{"id" => "00123", "n" => 42, "f" => 1.5, "b" => true, "e" => nil, "t" => " a <b> "}])

    assert_equal [["id", "n", "f", "b", "e", "t"], ["00123", 42, 1.5, true, nil, " a <b> "]], rows(path)
  end

  def test_empty_and_blank_strings_are_text_cells
    path = xlsx([{"a" => "", "b" => " ", "c" => "two\nlines"}])

    assert_includes sheet_xml(path), '<c r="A2" t="inlineStr"><is><t></t></is></c>'
    assert_equal [nil, " ", "two\nlines"], rows(path).last
  end

  def test_columns_select_order_and_name
    path = xlsx([{"id" => "1", "year" => 1851, "title" => "Moby"}], columns: {"Titel" => "title", "Nr." => "id"})

    assert_equal [["Titel", "Nr."], ["Moby", "1"]], rows(path)
  end

  def test_arrays_without_columns_have_no_header
    path = xlsx([[1, "x"], [2, "y"]])

    assert_equal [[1, "x"], [2, "y"]], rows(path)
    refute_includes sheet_xml(path), "autoFilter"
  end

  def test_header_false
    path = xlsx([{"id" => "1"}], header: false)

    assert_equal [["1"]], rows(path)
    refute_includes sheet_xml(path), "<pane"
  end

  def test_the_sheet_name
    assert_equal ["Bestand"], Roo::Excelx.new(xlsx([{"id" => "1"}], sheet: "Bestand")).sheets
  end

  # Header, widths and parts

  def test_every_part_is_xml
    parts(xlsx([{"a" => 1, "b" => "x"}], sheet: "Tom's")).each_value do |xml|
      assert_instance_of REXML::Document, REXML::Document.new(xml)
    end
  end

  def test_content_types_come_first
    assert_equal "[Content_Types].xml", parts(xlsx([{"a" => 1}])).keys.first
  end

  def test_the_header_is_bold_frozen_and_filtered
    path = xlsx([{"a" => 1, "b" => 2}, {"a" => 3}], sheet: "Bestand")
    xml = parts(path)

    assert_includes xml.fetch("xl/worksheets/sheet1.xml"), '<c r="A1" s="1" t="inlineStr">'
    assert_includes xml.fetch("xl/worksheets/sheet1.xml"), '<autoFilter ref="A1:B3"/>'
    assert_includes xml.fetch("xl/workbook.xml"), "'Bestand'!$A$1:$B$3</definedName>"
  end

  def test_widths_by_name
    xml = sheet_xml(xlsx([{"id" => "1", "title" => "Moby"}], widths: {"title" => 60}))

    assert_includes xml, '<cols><col min="2" max="2" width="60" customWidth="1"/></cols>'
  end

  def test_widths_by_position
    xml = sheet_xml(xlsx([[1, "Moby"]], widths: [8, 60.5]))

    assert_includes xml, '<col min="1" max="1" width="8" customWidth="1"/><col min="2" max="2" width="60.5"'
  end

  def test_a_width_for_an_unknown_column_is_an_error
    error = write_error([{"id" => "1"}], widths: {"Titel" => 60, "Jahr" => 8})

    assert_equal "widths: names columns that do not exist: Titel, Jahr", error.message
  end

  def test_with_columns_an_unknown_width_fails_in_open
    writer = Writer.new(File.join(@dir, "w.xlsx"), columns: ["id"], widths: {"Titel" => 60})

    assert_raises(Metacrunch::Error) { writer.open(nil) }
    writer.close
  end

  # Empty and aborted runs

  def test_an_empty_run_with_columns_has_the_header
    assert_equal [["id", "title"]], rows(xlsx([], columns: ["id", "title"]))
  end

  def test_an_empty_run_without_columns_is_an_empty_sheet
    assert_empty rows(xlsx([]))
  end

  def test_an_aborted_run_keeps_the_rows_so_far
    path = File.join(@dir, "aborted.xlsx")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write({"t" => "ok"}, ctx)
    assert_raises(Metacrunch::Error) { writer.write({"t" => Time.now}, ctx(2)) }
    writer.close

    assert_equal [["t"], ["ok"]], rows(path)
    assert_includes sheet_xml(path), '<autoFilter ref="A1:A2"/>'
  end

  def test_a_header_that_cannot_be_written_still_gives_a_file
    path = File.join(@dir, "header.xlsx")
    writer = Writer.new(path, columns: ["a\u0001"])
    error = assert_raises(Metacrunch::Error) { writer.open(nil) }
    writer.close

    assert_equal 'the header row: column "a\u0001" has a character that XML does not allow', error.message
    assert_empty rows(path)
  end

  def test_close_without_open_and_twice
    writer = Writer.new(File.join(@dir, "never.xlsx"))
    2.times { writer.close }

    refute_path_exists File.join(@dir, "never.xlsx")
  end

  # Errors

  def test_value_errors_name_the_position_and_the_column
    error = write_error([{"id" => "1"}, {"id" => Time.at(0)}])

    assert_equal 'record at position 2: column "id" is a Time; turn it into a String or a number in a step',
                 error.message
  end

  def test_errors_in_array_records_name_the_column_number
    error = write_error([[1, 10**15]])

    assert_match(/\Arecord at position 1: column 2 has more than 15 digits/, error.message)
  end

  def test_the_row_limit
    with_limit(:MAX_ROWS, 2) do
      error = write_error([{"a" => 1}, {"a" => 2}])

      assert_equal "record at position 2 would be row 3; Excel has 2 rows", error.message
    end
  end

  def test_the_column_limit
    with_limit(:MAX_COLUMNS, 2) do
      assert_equal "record at position 1 has 3 values; Excel has 2 columns", write_error([[1, 2, 3]]).message
    end
  end

  def test_column_model_errors
    error = write_error([{"a" => 1}, {"a" => 2, "b" => 3}])

    assert_match(/\Arecord at position 2 has the key "b", which the first record does not have/, error.message)
  end

  # Targets and batches

  def test_dash_is_stdout
    out, = capture_io do
      writer = Writer.new("-")
      writer.open(nil)
      writer.write({"a" => 1}, ctx)
      writer.close
    end
    path = File.join(@dir, "stdout.xlsx")
    File.binwrite(path, out)

    assert_equal [["a"], [1]], rows(path)
  end

  def test_a_batch_is_written_like_single_records
    path = File.join(@dir, "batch.xlsx")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write_batch([{"a" => 1}, {"a" => 2}], [ctx(1), ctx(2)])
    writer.close

    assert_equal [["a"], [1], [2]], rows(path)
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/writer_test.rb`
Expected: the file stops while loading with `uninitialized constant Metacrunch::Xlsx::Writer (NameError)`.

- [ ] **Step 3: Write `lib/metacrunch/xlsx/writer.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # A metacrunch sink: writes records as the rows of one worksheet to what
    # Metacrunch::Output takes (a path, "-" for stdout or an IO), streaming
    # in constant memory. A header row is bold, frozen and filtered. Cells
    # follow the Ruby type: String text, Integer and Float numbers, true and
    # false booleans, nil empty.
    class Writer

      FORBIDDEN = %r{[\[\]:*?/\\]}
      MAX_WIDTH = 255

      def initialize(target, columns: nil, header: true, sheet: "Sheet1", widths: nil)
        @output = Metacrunch::Output.new(target)
        @columns = Columns.new(columns)
        @header = check_header(header)
        @sheet_name = check_sheet(sheet)
        @widths = check_widths(widths)
        @zip = nil
      end

      def open(_context)
        @output.open
        @zip = ZipKit::Streamer.new(@output)
        Package::STATIC.each { |name, xml| @zip.write_deflated_file(name) { it << xml } }
        @sink = @zip.write_deflated_file("xl/worksheets/sheet1.xml")
        @sheet = Sheet.new(@sink)
        start if @columns.known?
      end

      def write(record, ctx)
        values = @columns.row(record, ctx)
        start unless @sheet.started?
        @sheet.row(values)
      rescue Cells::Unwritable => e
        raise Metacrunch::Error, message(e, "record at position #{ctx.position}")
      end

      # Writes the rows one by one into the compressed stream, which buffers
      # them.
      def write_batch(records, ctxs)
        records.zip(ctxs).each { |record, ctx| write(record, ctx) }
      end

      # Finishes the file, also after an aborted run, with the rows so far.
      def close
        finish if @zip
      ensure
        @zip = nil
        @output.close
      end

      private

      def check_header(header)
        return header if [true, false].include?(header)

        raise ArgumentError, "header: must be true or false, got #{header.inspect}"
      end

      def check_sheet(name)
        valid = name.is_a?(String) && name.length.between?(1, 31) && !name.match?(FORBIDDEN) &&
                !name.start_with?("'") && !name.end_with?("'")
        return name if valid

        raise ArgumentError, "sheet: must be 1 to 31 characters without [ ] : * ? / \\ and not start or end with ', " \
                             "got #{name.inspect}"
      end

      def check_widths(widths)
        values = widths.is_a?(Hash) ? widths.values : widths
        return widths if widths.nil? || (values.is_a?(Array) && values.all? { width?(it) })

        raise ArgumentError, "widths: must be a Hash of column name => width or an Array of widths " \
                             "(numbers above 0 and up to #{MAX_WIDTH}, or nil), got #{widths.inspect}"
      end

      def width?(value) = value.nil? || (value.is_a?(Numeric) && value.positive? && value <= MAX_WIDTH)

      def start
        names = @columns.names
        @sheet.start(@header ? names : nil, widths_by_position(names))
      rescue Cells::Unwritable => e
        raise Metacrunch::Error, message(e, "the header row")
      end

      def widths_by_position(names)
        return @widths unless @widths.is_a?(Hash)

        unknown = @widths.keys - names.to_a
        raise Metacrunch::Error, "widths: names columns that do not exist: #{unknown.join(", ")}" if unknown.any?

        names.map { @widths[it] }
      end

      # A sheet that never started (a run aborted before the first row) ends
      # without a header.
      def finish
        @sheet.start(nil, nil) unless @sheet.started?
        @sheet.finish
        @sink.close
        @zip.write_deflated_file("xl/workbook.xml") { it << Package.workbook(@sheet_name, @sheet.absolute_range) }
        @zip.close
      end

      def message(error, subject)
        return "#{subject} #{error.message}" if error.index.nil?

        names = @columns.names
        "#{subject}: column #{names ? names[error.index].inspect : error.index + 1} #{error.message}"
      end

    end
  end
end
```

In `lib/metacrunch/xlsx.rb`, below `require_relative "xlsx/package"`, add:

```ruby
require_relative "xlsx/writer"
```

`lib/metacrunch/xlsx.rb` is now complete:

```ruby
# frozen_string_literal: true

require "metacrunch"
require "zip_kit"
require_relative "xlsx/version"
require_relative "xlsx/columns"
require_relative "xlsx/cells"
require_relative "xlsx/sheet"
require_relative "xlsx/package"
require_relative "xlsx/writer"

module Metacrunch
  # XLSX for metacrunch: a sink (Writer) that streams one worksheet.
  module Xlsx
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -w -Itest -Ilib test/unit/writer_test.rb`
Expected: `29 runs, 0 failures, 0 errors`, no warnings.

- [ ] **Step 5: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `75 runs, 0 failures`; `Line coverage: 250 / 250 (100.00%)`, `Branch coverage: 109 / 109 (100.00%)`; `no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add Xlsx::Writer, a sink that streams one worksheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: metacrunch-xlsx: jobs, example, benchmark, docs and the check in Excel

**Files:**
- Create: `examples/report.rb`, `examples/data/books.jsonl`, `bench/xlsx.rb`, `Readme.md`, `CHANGELOG.md`
- Test: `test/integration/jobs_test.rb`, `test/integration/examples_test.rb`

**Interfaces:**
- Consumes: `Xlsx::Writer` (Task 9); `Metacrunch.job` with an Array as source, `Job#run`, `Metacrunch::JsonLines::Reader.new(targets)` and the `metacrunch` executable (core).

- [ ] **Step 1: Write the job tests**

`test/integration/jobs_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class JobsTest < Minitest::Test

  include Helpers

  RECORDS = [
    {"id" => "00123", "title" => "Metadata in practice", "year" => 2004, "copies" => 3},
    {"id" => "00124", "title" => "Cataloging, step by step", "year" => 2019, "copies" => nil}
  ].freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_report_with_and_without_workers
    expected = [
      ["Nr.", "Titel", "Jahr"],
      ["00123", "Metadata in practice", 2004],
      ["00124", "Cataloging, step by step", 2019]
    ]

    [nil, 2].each do |workers|
      path = File.join(@dir, "report-#{workers}.xlsx")
      result = report_job(path).run(workers:, logger: Logger.new(nil))

      assert_equal [:ok, expected], [result.status, rows(path)]
    end
  end

  def test_an_aborted_run_leaves_a_file_that_opens
    path = File.join(@dir, "aborted.xlsx")
    job = Metacrunch.job do
      source RECORDS
      map { it["id"] == "00124" ? raise("broken") : it }
      sink Metacrunch::Xlsx::Writer.new(path, columns: ["id", "title"])
    end
    result = job.run(logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_equal [["id", "title"], ["00123", "Metadata in practice"]], rows(path)
  end

  private

  def report_job(path)
    Metacrunch.job do
      source RECORDS
      sink Metacrunch::Xlsx::Writer.new(path, columns: {"Nr." => "id", "Titel" => "title", "Jahr" => "year"},
                                              widths: {"Titel" => 60})
    end
  end

end
```

- [ ] **Step 2: Run them**

Run: `bundle exec ruby -w -Itest -Ilib test/integration/jobs_test.rb`
Expected: `2 runs, 0 failures, 0 errors`. They check finished parts in the engine (workers, an aborted run), so they pass at once; a failure here is a finding about Task 9.

- [ ] **Step 3: Write the failing example test**

`test/integration/examples_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# Runs every example as a user would, through metacrunch's executable.
class ExamplesTest < Minitest::Test

  include Helpers

  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_report
    path = File.join(@dir, "report.xlsx")
    _stdout, stderr, status = metacrunch("run", example("report.rb"), "--target", path, example("data/books.jsonl"))

    assert_predicate status, :success?, stderr
    assert_equal ["Nr.", "Titel", "Jahr", "Exemplare", "Verfügbar"], rows(path).first
    assert_equal ["00124", "Cataloging, step by step", 2019, 0, false], rows(path)[2]
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, *)

end
```

Run: `bundle exec ruby -w -Itest -Ilib test/integration/examples_test.rb`
Expected: 1 failure: the example does not exist yet, and the failure shows metacrunch's error output.

- [ ] **Step 4: Write the example**

`examples/report.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch/xlsx"

# Writes a report of books as an Excel file: German column names and a wide
# title column. The header row is bold, frozen and filtered; numbers of
# copies are numbers, the "00123" numbers stay text.
#
#   bundle exec metacrunch run examples/report.rb --target tmp/report.xlsx examples/data/books.jsonl
#
# The parameter is not called output: metacrunch's own -o/--output, given
# before the job file, would replace the Excel sink with JSON Lines.
Metacrunch.job do
  params do
    param :target, String, default: "report.xlsx", desc: "Excel file for the report"
    args :files, min: 1
  end

  source Metacrunch::JsonLines::Reader.new(params.files)

  map { it.merge("available" => it["copies"].to_i.positive?) }

  sink Metacrunch::Xlsx::Writer.new(
    params.target,
    columns: {"Nr." => "id", "Titel" => "title", "Jahr" => "year", "Exemplare" => "copies", "Verfügbar" => "available"},
    sheet: "Bestand",
    widths: {"Titel" => 60}
  )
end
```

`examples/data/books.jsonl`:

```
{"id": "00123", "title": "Metadata in practice", "year": 2004, "copies": 3}
{"id": "00124", "title": "Cataloging, step by step", "year": 2019, "copies": 0}
{"id": "00125", "title": "The \"quoted\" title", "year": null, "copies": 1}
{"id": "00126", "title": "Müller's guide to indexing", "year": 1998, "copies": 12}
```

Run: `bundle exec ruby -w -Itest -Ilib test/integration/examples_test.rb`
Expected: `1 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Write and run the benchmark**

`bench/xlsx.rb`:

```ruby
# frozen_string_literal: true

# Writes 100,000 rows of 10 text cells and fails when it takes more than 2 s
# or the process holds more than 50 MB at the end (the writer streams, so
# memory stays flat while it runs).
#
#   bundle exec ruby --yjit bench/xlsx.rb [rows]
require "logger"
require "tmpdir"
require "metacrunch/xlsx"

ROWS = Integer(ARGV.fetch(0, 100_000))
SECONDS = 2.0
MEGABYTES = 50

names = Array.new(10) { "column #{it}" }
records = Array.new(1000) { |row| names.each_with_index.to_h { |name, index| [name, "value #{row} #{index}"] } }
ctx = Metacrunch::Context.new(id: 1, position: 1, logger: Logger.new(nil))

Dir.mktmpdir do |dir|
  path = File.join(dir, "out.xlsx")
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  writer = Metacrunch::Xlsx::Writer.new(path)
  writer.open(nil)
  ROWS.times { writer.write(records[it % records.size], ctx) }
  writer.close
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  megabytes = Integer(`ps -o rss= -p #{Process.pid}`) / 1024

  puts format("%<rows>d rows: %<seconds>.2f s, %<megabytes>d MB, file %<size>d KB",
              rows: ROWS, seconds:, megabytes:, size: File.size(path) / 1024)
  exit(1) if seconds > SECONDS || megabytes > MEGABYTES
end
```

Run: `bundle exec ruby --yjit bench/xlsx.rb`
Expected: a line such as `100000 rows: 1.07 s, 43 MB, file 3331 KB`, exit status 0. Above 2 s or 50 MB, the script exits with 1: stop and find the cause.

- [ ] **Step 6: Write the docs**

`Readme.md`:

````markdown
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

```ruby
# Gemfile
gem "metacrunch-xlsx"
```

Requires Ruby 4.0 and metacrunch 5. The only other dependency is [zip_kit](https://github.com/julik/zip_kit), which
writes the ZIP container.

## The writer

| Option | Default | |
|---|---|---|
| `columns` | `nil` | `nil`: the keys of the first record; an Array of keys; a Hash of header name => key |
| `header` | `true` | write a header row: bold, frozen (the rows scroll below it) and with an autofilter |
| `sheet` | `"Sheet1"` | the worksheet's name: 1 to 31 characters, none of `[ ] : * ? / \`, not starting or ending with `'` |
| `widths` | `nil` | column widths in characters, up to 255: a Hash of header name => width, or an Array by position |

The target is what `Metacrunch::Output` takes: a path, `"-"` for stdout, or an IO. Without `widths:` Excel's default
width applies; a streaming writer cannot fit widths to the content.

### Columns

- With `columns:`, other keys of a record are not written and missing keys are empty cells; the header row is written
  when the run starts, so an empty run gives a file with the header only.
- Without `columns:`, the first record's keys are the columns; a later record with another key stops the run (name the
  columns with `columns:`). An empty run gives an empty sheet.
- Array records are written as they are; with `columns:` the header comes from it, without it there is no header.

### Cells

| Value | Cell |
|---|---|
| `String` | text; `"00123"` stays text |
| `Integer` (up to 15 digits), `Float` | number |
| `true`, `false` | boolean |
| `nil` | empty |

These stop the run with the record's position, e.g. `record at position 7: column "date" is a Time; turn it into a
String or a number in a step`:

- other values: a `Time`, a `Date`, an Array, `NaN`, `Infinity`;
- an Integer with more than 15 digits, which Excel would change (it keeps 15 significant digits): write it as a
  String;
- text with a control character other than tab and line breaks, which XML cannot hold;
- text longer than 32,767 characters, row 1,048,577 (the header counts), more than 16,384 columns: Excel's limits.

When a run aborts, the writer still finishes the file, with the rows written so far, so it opens in Excel.

## Upgrading from metacrunch-file

The XLSX sink of the 4.x gem metacrunch-file is replaced by this gem.

| metacrunch-file 4.x | metacrunch-xlsx |
|---|---|
| `File::XLSXDestination.new(path, ["ID", "Titel"], worksheet_title: "Bestand")` | `Xlsx::Writer.new(path, columns: ["ID", "Titel"], sheet: "Bestand")` with Array records |
| every cell is text | cells by Ruby type: turn numbers into Strings in a step to keep them as text |
| `write` takes a row or an Array of rows | one record is one row |
| the workbook is kept in memory until `close` | rows are streamed |

## License

MIT; see [License.txt](License.txt).
````

`CHANGELOG.md`:

````markdown
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
````

- [ ] **Step 7: Ask the user to open a file in Excel**

Run: `bundle exec metacrunch run examples/report.rb --target tmp/report.xlsx examples/data/books.jsonl`
Expected: exit status 0 and the file `tmp/report.xlsx` (ignored by git).

Ask the user to open `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-xlsx/tmp/report.xlsx` in Excel and to check (spec 8.4): no repair message; the sheet is called "Bestand"; the header row is bold, stays at the top when scrolling and has filter buttons; "00123" is text (left-aligned, no number warning needed), "Jahr" and "Exemplare" are numbers (right-aligned), "Verfügbar" shows booleans; the title column is wide. Do not wait for the answer: go on with Step 8 and Task 11, and put the answer (or that it is pending) in the final report. A repair message is a Critical finding for the final review.

- [ ] **Step 8: Run the whole gem and commit**

Run: `bundle exec rake`
Expected: `78 runs, 0 failures`; `Line coverage: 250 / 250 (100.00%)`, `Branch coverage: 109 / 109 (100.00%)`; `21 files inspected, no offenses detected`.

Run the invisible-character check, then:

```bash
git add -A
git commit -m "Add job tests, an example, a benchmark, Readme and CHANGELOG

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: metacrunch core: name the gems in the docs

**Files:**
- Modify: `Readme.md` (the paragraph on extension gems, around line 54), `docs/files.md` (the first paragraph)

All commands of this task run in the core worktree `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch/.claude/worktrees/metacrunch-ng-csv-xlsx`.

- [ ] **Step 1: Rewrite the Readme's paragraph on extension gems**

Replace this paragraph of `Readme.md`:

```markdown
The extension gems of 4.x (`metacrunch-file`, `metacrunch-marcxml`, `metacrunch-elasticsearch`, `metacrunch-db`,
`metacrunch-redis`) do not work with metacrunch 5 yet. Until they are ported, JSON Lines is built in, and any other
source or sink is a small class of your own (see [Sources](docs/jobs.md#sources) and [Sinks](docs/jobs.md#sinks)),
built on `Metacrunch::Input` and `Metacrunch::Output`, which read gzip and tar and take care of stdin, stdout and
pipes (see [Files](docs/files.md)).
```

with:

```markdown
JSON Lines is built in. Extension gems for metacrunch 5, not released yet either, read and write other formats:
`metacrunch-marcxml` (MARCXML), `metacrunch-csv` (CSV) and `metacrunch-xlsx` (Excel files). Together with
`Metacrunch::Input` and `Metacrunch::Output` they replace the 4.x gem `metacrunch-file`; `metacrunch-elasticsearch`,
`metacrunch-db` and `metacrunch-redis` do not work with metacrunch 5 yet. Any other source or sink is a small class of
your own (see [Sources](docs/jobs.md#sources) and [Sinks](docs/jobs.md#sinks)), built on `Metacrunch::Input` and
`Metacrunch::Output`, which read gzip and tar and take care of stdin, stdout and pipes (see [Files](docs/files.md)).
```

- [ ] **Step 2: Name the gems in `docs/files.md`**

Replace the first paragraph of `docs/files.md`:

```markdown
Sources and sinks that read or write files can leave opening, decompressing and the details of stdin, stdout and pipes
to two building blocks: `Metacrunch::Input` and `Metacrunch::Output`. `JsonLines::Reader` and `JsonLines::Writer` are
built on them, and so are the sources and sinks that `metacrunch generate` creates.
```

with:

```markdown
Sources and sinks that read or write files can leave opening, decompressing and the details of stdin, stdout and pipes
to two building blocks: `Metacrunch::Input` and `Metacrunch::Output`. `JsonLines::Reader` and `JsonLines::Writer` are
built on them, and so are the sources and sinks that `metacrunch generate` creates and those of the extension gems
`metacrunch-marcxml`, `metacrunch-csv` and `metacrunch-xlsx`.
```

- [ ] **Step 3: Check and commit**

Run: `git diff --stat`
Expected: `Readme.md` and `docs/files.md` changed, nothing else.

```bash
git add Readme.md docs/files.md
git commit -m "Name metacrunch-csv and metacrunch-xlsx in the docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## After the last task

Per the workflow: one fresh reviewer on the most capable model reviews both gem repositories (`master` from their first commit) and the core branch `metacrunch-ng-csv-xlsx` (from da1c474) against the spec and this plan, with the Review Focus above. Critical and Important findings are fixed; the minors are offered to the user. The answer to Task 10, Step 7 goes into the final report.

Creating the GitHub repositories `ubpb/metacrunch-csv` and `ubpb/metacrunch-xlsx`, pushing, and merging the core branch into `metacrunch-ng` stay with the user: ask first. The gems' CI can only run once the repositories exist.
