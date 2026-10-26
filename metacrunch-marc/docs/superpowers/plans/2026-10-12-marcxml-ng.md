# metacrunch-marcxml 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild metacrunch-marcxml for metacrunch 5: an ordered, faithful MARCXML record model with a pure Ruby API, a fast Ox SAX parser, a serializer, a splitter, and a metacrunch source (`Reader`) and sink (`Writer`).

**Architecture:** A core (model, parser, splitter, serializer) under `Metacrunch::Marcxml` that does not reference metacrunch, plus two components (`Reader`, `Writer`) that do. Records hold plain Arrays of fields and subfields; queries filter them. Parsing streams through Ox SAX from IO-like objects; Strings are wrapped in a `readpartial` reader because Ox is superlinear on `String`/`StringIO`.

**Tech Stack:** Ruby 4.0, Ox 2.14 (SAX), metacrunch 5 (`metacrunch-ng` branch), Minitest, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-12-marcxml-ng-design.md`

## Global Constraints

- Work in the worktree `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-marcxml/.claude/worktrees/metacrunch-ng` on branch `metacrunch-ng`. Never push.
- Before any `bundle` command: `export METACRUNCH_PATH=/Users/renspr/Code/Projects/upb/metacrunch/metacrunch` (the worktree is not next to the metacrunch checkout).
- Ruby >= 4.0. Runtime dependencies exactly: `ox` (`~> 2.14`) and `metacrunch` (`>= 5.0.0.pre`, `< 6`). No ActiveSupport.
- `Metacrunch::Marcxml::VERSION = "5.0.0.pre"`.
- Only `lib/metacrunch/marcxml/reader.rb` and `lib/metacrunch/marcxml/writer.rb` may `require "metacrunch"` or reference metacrunch classes.
- Every Ruby file starts with `# frozen_string_literal: true`. RuboCop (rubocop-ubpb `ruby.yml`) must pass: double quotes, `[:a, :b]` and `["a", "b"]` instead of `%i`/`%w`, empty lines inside class bodies except for pure namespace modules.
- Coverage on full runs: line >= 95 %, branch >= 90 %.
- Docs, comments, messages and commit messages in English; examples and fixtures generic (no names of internal systems or institutions).
- One commit per task, message in the imperative, ending with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A file whose values are not valid UTF-8 (e.g. a Latin-1 export): the parser raises `ParseError` naming the field, and the `Reader` yields an `InvalidRecord`, instead of a crash later in the writer. (Spec amendment in Task 4; tests in Tasks 4 and 7.)
2. A byte order mark at the start of a file or string: read normally. (Test in Task 4.)
3. CRLF line endings inside values: XML turns them into `\n`; a `\r` set in Ruby survives `to_xml` and parsing. (Tests in Tasks 4 and 6.)
4. An empty `<record></record>` or `<record/>`: a `Record` without fields, which the splitter cuts and the writer writes. (Tests in Tasks 4, 5 and 8.)
5. Concatenated documents (`cat a.xml b.xml`, or bare records without `<collection>`): `each_xml` and the `Reader` read every record; `Marcxml.each` raises `ParseError` because the input is not well-formed XML. (Tests in Tasks 4, 5 and 7.)

---

### Task 1: Scaffold the gem for metacrunch 5

Replace the 4.x code, specs and tooling with an empty, lint-clean, tested gem skeleton.

**Files:**
- Delete: `lib/metacrunch/marcxml/parser.rb`, `lib/metacrunch/marcxml/record.rb`, `lib/metacrunch/marcxml/record/` (all), `spec/` (all), `.rspec`, `.yardopts`, `bin/console`, `.circleci/config.yml`
- Replace: `metacrunch-marcxml.gemspec`, `Gemfile`, `Rakefile`, `.gitignore`, `lib/metacrunch/marcxml.rb`, `lib/metacrunch/marcxml/version.rb`
- Create: `.rubocop.yml`, `.github/workflows/ci.yml`, `lib/metacrunch/marcxml/errors.rb`, `test/test_helper.rb`, `test/unit/marcxml_test.rb`

**Interfaces:**
- Produces: `Metacrunch::Marcxml::VERSION`, `Metacrunch::Marcxml::NAMESPACE` (`"http://www.loc.gov/MARC21/slim"`), `Metacrunch::Marcxml::Error < StandardError`, `ParseError < Error` (`#line`, `#column`, `ParseError.new(message, line: nil, column: nil)`), `SerializeError < Error`.

- [ ] **Step 1: Remove the 4.x files**

```bash
cd /Users/renspr/Code/Projects/upb/metacrunch/metacrunch-marcxml/.claude/worktrees/metacrunch-ng
git rm -r -q lib/metacrunch/marcxml/parser.rb lib/metacrunch/marcxml/record.rb lib/metacrunch/marcxml/record spec .rspec .yardopts bin/console .circleci
```

- [ ] **Step 2: Write the tooling files**

`metacrunch-marcxml.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/metacrunch/marcxml/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-marcxml"
  spec.version  = Metacrunch::Marcxml::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "MARCXML for metacrunch: an ordered record model, a fast parser, a source and a sink"
  spec.homepage = "https://github.com/ubpb/metacrunch-marcxml"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"
  spec.add_dependency "ox", "~> 2.14"
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

`.rubocop.yml`:

```yaml
inherit_gem:
  rubocop-ubpb: ruby.yml

inherit_mode:
  merge:
    - Exclude

Style/FrozenStringLiteralComment:
  Enabled: true

# Tests and the benchmark load what they have just dumped.
Security/MarshalLoad:
  Exclude:
    - "test/**/*"
    - "bench/**/*"
```

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [master, metacrunch-ng]
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

- [ ] **Step 3: Write the failing test**

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
    add_filter "/test/"
    add_filter "/vendor/"
  end
end

require "minitest/autorun"
require "stringio"
require "tmpdir"
require "fileutils"
require "zlib"
require "metacrunch/marcxml"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
```

`test/unit/marcxml_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class MarcxmlTest < Minitest::Test

  def test_version
    assert_equal "5.0.0.pre", Metacrunch::Marcxml::VERSION
  end

  def test_namespace
    assert_equal "http://www.loc.gov/MARC21/slim", Metacrunch::Marcxml::NAMESPACE
  end

  def test_parse_error_names_the_position
    error = Metacrunch::Marcxml::ParseError.new("bad", line: 3, column: 7)

    assert_equal "bad (line 3, column 7)", error.message
    assert_equal [3, 7], [error.line, error.column]
  end

  def test_parse_error_without_a_position
    error = Metacrunch::Marcxml::ParseError.new("bad")

    assert_equal "bad", error.message
    assert_nil error.line
  end

  def test_errors_share_a_base_class
    assert_operator Metacrunch::Marcxml::ParseError, :<, Metacrunch::Marcxml::Error
    assert_operator Metacrunch::Marcxml::SerializeError, :<, Metacrunch::Marcxml::Error
  end

end
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `export METACRUNCH_PATH=/Users/renspr/Code/Projects/upb/metacrunch/metacrunch && bundle install && bundle exec ruby -Ilib -Itest test/unit/marcxml_test.rb`
Expected: FAIL (`uninitialized constant Metacrunch::Marcxml::NAMESPACE` / `ParseError`).

- [ ] **Step 5: Write the implementation**

`lib/metacrunch/marcxml/version.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml

    VERSION = "5.0.0.pre"

  end
end
```

`lib/metacrunch/marcxml/errors.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml

    # Base class of the errors of this library.
    class Error < StandardError; end

    # Input that is not well-formed MARCXML. line and column are positions
    # in the input as Ox reports them, or nil.
    class ParseError < Error

      attr_reader :line, :column

      def initialize(message, line: nil, column: nil)
        @line = line
        @column = column
        super(line ? "#{message} (line #{line}, column #{column})" : message)
      end

    end

    # A record that cannot be written as MARCXML.
    class SerializeError < Error; end

  end
end
```

`lib/metacrunch/marcxml.rb`:

```ruby
# frozen_string_literal: true

require_relative "marcxml/version"
require_relative "marcxml/errors"

module Metacrunch
  # MARCXML for metacrunch: an ordered record model (Record, ControlField,
  # DataField, Subfield), a parser, a serializer, and a source (Reader) and
  # a sink (Writer). Only Reader and Writer depend on metacrunch.
  module Marcxml

    # The namespace of the MARC 21 XML schema.
    NAMESPACE = "http://www.loc.gov/MARC21/slim"

  end
end
```

- [ ] **Step 6: Run the tests and the linter**

Run: `bundle exec rake`
Expected: 5 runs, 0 failures; RuboCop "no offenses detected". Fix any offense RuboCop reports (`bundle exec rubocop -a` for layout) before going on.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold the gem for metacrunch 5" -m "Removes the 4.x code, the RSpec specs, CircleCI and YARD. Adds Minitest, SimpleCov, rubocop-ubpb, GitHub Actions and the error classes." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Subfield, ControlField and DataField

**Files:**
- Create: `lib/metacrunch/marcxml/subfield.rb`, `lib/metacrunch/marcxml/control_field.rb`, `lib/metacrunch/marcxml/data_field.rb`
- Modify: `lib/metacrunch/marcxml.rb` (requires)
- Test: `test/unit/subfield_test.rb`, `test/unit/control_field_test.rb`, `test/unit/data_field_test.rb`

**Interfaces:**
- Produces:
  - `Subfield.new(code, value)`; `#code`, `#value` (accessors); `==`, `eql?`, `hash`; `#to_h` → `{code => value}`; `#to_s`/`#inspect` → `"$aValue"`; `dup` copies the strings.
  - `ControlField.new(tag, value)`; `#tag`, `#value`; `#[](index)` → `value&.[](index)`; `==`, `eql?`, `hash`; `#to_h` → `{tag => value}`; `#to_s`/`#inspect` → `"=001  value"`.
  - `DataField::BLANK = " "`; `DataField.new(tag, ind1 = " ", ind2 = " ", subfields = [])` (Subfields or `[code, value]` pairs; anything else → `ArgumentError`); `#tag` accessor; `#ind1`, `#ind2` with setters (nil → `" "`); `#subfields(*codes)` (no codes → own Array); `#values(*codes)`; `#value(*codes)`; `#[](code)`; `#join(*codes, separator: " ")` → String or nil; `#add(code, value)` → self; `#remove(*codes)` → removed Array (no codes → all); `==`, `eql?`, `hash`; `#to_h` → `{tag => {"ind1" =>, "ind2" =>, "subfields" => [...]}}`; `#to_s`/`#inspect` → `"=245  10$aTitle"` with blank shown as `\`; `dup` is deep.

- [ ] **Step 1: Write the failing tests**

`test/unit/subfield_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class SubfieldTest < Minitest::Test

  Subfield = Metacrunch::Marcxml::Subfield

  def test_has_a_code_and_a_value
    subfield = Subfield.new("a", "Title")

    assert_equal "a", subfield.code
    assert_equal "Title", subfield.value
  end

  def test_equal_with_the_same_code_and_value
    assert_equal Subfield.new("a", "x"), Subfield.new("a", "x")
    assert_operator Subfield.new("a", "x"), :eql?, Subfield.new("a", "x")
    assert_equal Subfield.new("a", "x").hash, Subfield.new("a", "x").hash
  end

  def test_not_equal_with_another_code_or_value
    refute_equal Subfield.new("a", "x"), Subfield.new("b", "x")
    refute_equal Subfield.new("a", "x"), Subfield.new("a", "y")
  end

  def test_to_h_is_marc_in_json
    assert_equal({"a" => "Title"}, Subfield.new("a", "Title").to_h)
  end

  def test_text_form
    assert_equal "$aTitle", Subfield.new("a", "Title").to_s
    assert_equal "$aTitle", Subfield.new("a", "Title").inspect
  end

  def test_dup_copies_the_strings
    original = Subfield.new("a", +"Title")
    copy = original.dup
    copy.value << "!"

    assert_equal "Title", original.value
  end

end
```

`test/unit/control_field_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ControlFieldTest < Minitest::Test

  ControlField = Metacrunch::Marcxml::ControlField

  def test_has_a_tag_and_a_value
    field = ControlField.new("001", "123")

    assert_equal "001", field.tag
    assert_equal "123", field.value
  end

  def test_brackets_read_positions_of_the_value
    field = ControlField.new("008", "#{"x" * 35}ger d")

    assert_equal "ger", field[35..37]
    assert_equal "g", field[35]
  end

  def test_brackets_on_a_nil_value
    assert_nil ControlField.new("008", nil)[35..37]
  end

  def test_equality
    assert_equal ControlField.new("001", "1"), ControlField.new("001", "1")
    refute_equal ControlField.new("001", "1"), ControlField.new("003", "1")
    assert_equal ControlField.new("001", "1").hash, ControlField.new("001", "1").hash
  end

  def test_to_h_is_marc_in_json
    assert_equal({"001" => "123"}, ControlField.new("001", "123").to_h)
  end

  def test_text_form
    assert_equal "=001  123", ControlField.new("001", "123").to_s
    assert_equal "=001  123", ControlField.new("001", "123").inspect
  end

  def test_dup_copies_the_strings
    original = ControlField.new("001", +"123")
    copy = original.dup
    copy.value << "4"

    assert_equal "123", original.value
  end

end
```

`test/unit/data_field_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class DataFieldTest < Minitest::Test

  DataField = Metacrunch::Marcxml::DataField
  Subfield = Metacrunch::Marcxml::Subfield

  def title
    DataField.new("245", "1", "0", [["a", "Title"], ["b", "Subtitle"], ["c", "Jane Doe"], ["a", "Second"]])
  end

  def test_indicators_default_to_blank
    field = DataField.new("500")

    assert_equal [" ", " "], [field.ind1, field.ind2]
    assert_empty field.subfields
  end

  def test_nil_indicators_become_blank
    field = DataField.new("500", nil, nil)
    field.ind1 = nil
    field.ind2 = "1"

    assert_equal [" ", "1"], [field.ind1, field.ind2]
  end

  def test_subfields_from_pairs_and_subfields
    field = DataField.new("100", "1", " ", [["a", "Doe, Jane"], Subfield.new("4", "aut")])

    assert_equal [Subfield.new("a", "Doe, Jane"), Subfield.new("4", "aut")], field.subfields
  end

  def test_rejects_other_subfield_values
    error = assert_raises(ArgumentError) { DataField.new("100", " ", " ", [{"a" => "x"}]) }

    assert_match(/a subfield must be a Subfield or a \[code, value\] pair/, error.message)
  end

  def test_subfields_without_codes_is_the_fields_own_array
    field = title
    field.subfields << Subfield.new("x", "added")

    assert_equal "added", field.subfields.last.value
  end

  def test_subfields_with_codes_keep_the_field_order
    assert_equal ["a", "b", "a"], title.subfields("b", "a").map(&:code)
  end

  def test_values
    assert_equal ["Title", "Subtitle", "Jane Doe", "Second"], title.values
    assert_equal ["Title", "Second"], title.values("a")
    assert_equal ["Title", "Subtitle", "Second"], title.values("b", "a")
  end

  def test_value_is_the_first_value
    assert_equal "Title", title.value
    assert_equal "Subtitle", title.value("b")
    assert_nil title.value("z")
  end

  def test_brackets_read_the_first_value_of_a_code
    assert_equal "Jane Doe", title["c"]
  end

  def test_join
    assert_equal "Title : Subtitle : Second", title.join("a", "b", separator: " : ")
    assert_equal "Title Second", title.join("a")
    assert_nil title.join("z")
  end

  def test_add_appends_a_subfield
    field = title
    result = field.add("n", "Part 1")

    assert_same field, result
    assert_equal Subfield.new("n", "Part 1"), field.subfields.last
  end

  def test_remove_returns_the_removed_subfields
    field = title
    removed = field.remove("a")

    assert_equal ["Title", "Second"], removed.map(&:value)
    assert_equal ["b", "c"], field.subfields.map(&:code)
  end

  def test_remove_without_codes_removes_all
    field = title
    field.remove

    assert_empty field.subfields
  end

  def test_equality_compares_tag_indicators_and_subfield_order
    assert_equal title, title
    refute_equal title, DataField.new("245", "1", "0", title.subfields.reverse)
    refute_equal title, DataField.new("245", "0", "0", title.subfields)
  end

  def test_equal_fields_have_the_same_hash
    assert_equal title.hash, title.hash
  end

  def test_to_h_is_marc_in_json
    expected = {"650" => {"ind1" => " ", "ind2" => "7", "subfields" => [{"a" => "Metadata"}, {"2" => "gnd"}]}}

    assert_equal expected, DataField.new("650", " ", "7", [["a", "Metadata"], ["2", "gnd"]]).to_h
  end

  def test_text_form_shows_blank_indicators_as_backslash
    field = DataField.new("650", " ", "7", [["a", "Metadata"], ["2", "gnd"]])

    assert_equal "=650  \\7$aMetadata$2gnd", field.to_s
    assert_equal field.to_s, field.inspect
  end

  def test_dup_copies_subfields_and_strings
    original = title
    copy = original.dup
    copy.subfields.first.value << "!"
    copy.add("x", "new")

    assert_equal "Title", original.value("a")
    assert_equal 4, original.subfields.size
  end

end
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `bundle exec ruby -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/subfield_test.rb test/unit/control_field_test.rb test/unit/data_field_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Marcxml::Subfield` (and the other two classes).

- [ ] **Step 3: Write the implementation**

`lib/metacrunch/marcxml/subfield.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A subfield of a data field: a code and a value, both Strings.
    class Subfield

      attr_accessor :code, :value

      def initialize(code, value)
        @code = code
        @value = value
      end

      def ==(other)
        other.instance_of?(Subfield) && other.code == code && other.value == value
      end

      alias eql? ==

      def hash = [Subfield, code, value].hash

      # MARC-in-JSON: {"a" => "Title"}.
      def to_h = {code => value}

      # "$aTitle", as in the mnemonic form of MarcEdit.
      def to_s = "$#{code}#{value}"

      alias inspect to_s

      private

      # dup and clone copy the strings, so a copy can be changed in place.
      def initialize_copy(source)
        super
        @code = source.code&.dup
        @value = source.value&.dup
      end

    end
  end
end
```

`lib/metacrunch/marcxml/control_field.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A control field (001-009 in MARC 21): a tag and a value.
    class ControlField

      attr_accessor :tag, :value

      def initialize(tag, value)
        @tag = tag
        @value = value
      end

      # value[index], e.g. field[35..37] for the language in 008; nil if
      # there is no value.
      def [](index) = value&.[](index)

      def ==(other)
        other.instance_of?(ControlField) && other.tag == tag && other.value == value
      end

      alias eql? ==

      def hash = [ControlField, tag, value].hash

      # MARC-in-JSON: {"001" => "123"}.
      def to_h = {tag => value}

      # "=001  123", as in the mnemonic form of MarcEdit.
      def to_s = "=#{tag}  #{value}"

      alias inspect to_s

      private

      def initialize_copy(source)
        super
        @tag = source.tag&.dup
        @value = source.value&.dup
      end

    end
  end
end
```

`lib/metacrunch/marcxml/data_field.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A data field: a tag, two indicators and an ordered Array of Subfields.
    # A blank indicator is " ".
    class DataField

      BLANK = " "

      attr_accessor :tag
      attr_reader :ind1, :ind2

      # subfields: Subfields or [code, value] pairs.
      def initialize(tag, ind1 = BLANK, ind2 = BLANK, subfields = [])
        @tag = tag
        self.ind1 = ind1
        self.ind2 = ind2
        @subfields = subfields.map { subfield(it) }
      end

      # nil becomes " ".
      def ind1=(value)
        @ind1 = value.nil? ? BLANK : value
      end

      # nil becomes " ".
      def ind2=(value)
        @ind2 = value.nil? ? BLANK : value
      end

      # Without codes the field's own Array (changes affect the field), with
      # codes a new Array of the subfields with these codes, in field order.
      def subfields(*codes)
        codes.empty? ? @subfields : @subfields.select { codes.include?(it.code) }
      end

      # The values of the subfields with these codes (all without codes), in
      # field order.
      def values(*codes) = subfields(*codes).map(&:value)

      # The first value of these codes (of any code without codes), or nil.
      def value(*codes)
        found = codes.empty? ? @subfields.first : @subfields.find { codes.include?(it.code) }
        found&.value
      end

      def [](code) = value(code)

      # The values of these codes joined, or nil if there is none.
      def join(*codes, separator: " ")
        found = values(*codes)
        found.empty? ? nil : found.join(separator)
      end

      # Appends a subfield. Returns self.
      def add(code, value)
        @subfields << Subfield.new(code, value)
        self
      end

      # Removes the subfields with these codes (all without codes). Returns
      # them.
      def remove(*codes)
        removed = []
        @subfields.reject! do |subfield|
          match = codes.empty? || codes.include?(subfield.code)
          removed << subfield if match
          match
        end
        removed
      end

      def ==(other)
        other.instance_of?(DataField) && other.tag == tag && other.ind1 == ind1 && other.ind2 == ind2 &&
          other.subfields == subfields
      end

      alias eql? ==

      def hash = [DataField, tag, ind1, ind2, @subfields].hash

      # MARC-in-JSON: {"245" => {"ind1" => "1", "ind2" => "0", "subfields" => [{"a" => "Title"}]}}.
      def to_h
        {tag => {"ind1" => ind1, "ind2" => ind2, "subfields" => @subfields.map(&:to_h)}}
      end

      # "=245  10$aTitle", as in the mnemonic form of MarcEdit; a blank
      # indicator is "\".
      def to_s = "=#{tag}  #{mnemonic(ind1)}#{mnemonic(ind2)}#{@subfields.join}"

      alias inspect to_s

      private

      def initialize_copy(source)
        super
        @tag = source.tag&.dup
        @ind1 = source.ind1.dup
        @ind2 = source.ind2.dup
        @subfields = source.subfields.map(&:dup)
      end

      def subfield(value)
        return value if value.is_a?(Subfield)
        return Subfield.new(*value) if value.is_a?(Array) && value.size == 2

        raise ArgumentError, "a subfield must be a Subfield or a [code, value] pair, got #{value.inspect}"
      end

      def mnemonic(indicator) = indicator == BLANK ? "\\" : indicator

    end
  end
end
```

In `lib/metacrunch/marcxml.rb`, replace the require lines with:

```ruby
require_relative "marcxml/version"
require_relative "marcxml/errors"
require_relative "marcxml/subfield"
require_relative "marcxml/control_field"
require_relative "marcxml/data_field"
```

- [ ] **Step 4: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no RuboCop offenses. Split a test if `Minitest/MultipleAssertions` complains.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add Subfield, ControlField and DataField" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Record and field selection

**Files:**
- Create: `lib/metacrunch/marcxml/filter.rb`, `lib/metacrunch/marcxml/record.rb`
- Modify: `lib/metacrunch/marcxml.rb` (requires)
- Test: `test/unit/record_test.rb`

**Interfaces:**
- Consumes: `Subfield`, `ControlField`, `DataField` (Task 2).
- Produces:
  - `Filter.new(tags, ind1, ind2)` (internal), `#match?(field)`; tag matchers String, Array, Range of Strings, Regexp; `ArgumentError` for others; indicator filters nil, String, Array of Strings.
  - `Record.new(leader: nil, fields: [], type: nil)`; `#leader`, `#type` accessors; `#fields(*tags, ind1: nil, ind2: nil)` (no arguments → own Array); `#field(*tags, ind1:, ind2:)`; `#[](tag)`; `#values(tags, *codes, ind1:, ind2:)`; `#value(tags, *codes, ind1:, ind2:)`; `#add(field)` → self; `#append(field)` → self; `#remove(*tags, ind1:, ind2:)` → removed Array; `==`, `eql?`, `hash`; deep `dup`; `#to_h`; `#to_s`; `#inspect`.

- [ ] **Step 1: Write the failing test**

`test/unit/record_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class RecordTest < Minitest::Test

  Record = Metacrunch::Marcxml::Record
  ControlField = Metacrunch::Marcxml::ControlField
  DataField = Metacrunch::Marcxml::DataField

  def sample
    Record.new(
      leader: "00000nam a2200000 c 4500",
      type: "Bibliographic",
      fields: [
        ControlField.new("001", "123"),
        ControlField.new("008", "#{"x" * 35}ger d"),
        DataField.new("100", "1", " ", [["a", "Doe, Jane"], ["4", "aut"]]),
        DataField.new("245", "1", "0", [["a", "Title"], ["b", "Subtitle"]]),
        DataField.new("650", " ", "7", [["a", "Metadata"], ["2", "gnd"]]),
        DataField.new("650", " ", "4", [["a", "Libraries"]]),
        DataField.new("700", "1", " ", [["a", "Roe, Richard"]]),
        DataField.new("852H", "8", " ", [["b", "MAIN"], ["as", "available"]]),
        DataField.new("856", "4", "0", [["u", "https://example.org/1"]]),
        DataField.new("856", "4", "2", [["u", "https://example.org/2"], ["z", "Cover"]])
      ]
    )
  end

  def tags(fields) = fields.map(&:tag)

  def test_defaults
    record = Record.new

    assert_nil record.leader
    assert_nil record.type
    assert_empty record.fields
  end

  def test_rejects_objects_that_are_not_fields
    error = assert_raises(ArgumentError) { Record.new(fields: ["001"]) }

    assert_match(/a field must be a ControlField or a DataField/, error.message)
  end

  def test_fields_without_arguments_is_the_records_own_array
    record = sample
    record.fields << ControlField.new("009", "x")

    assert_equal "009", record.fields.last.tag
  end

  def test_fields_by_tag
    assert_equal ["650", "650"], tags(sample.fields("650"))
    assert_equal ["100", "700"], tags(sample.fields("700", "100"))
    assert_equal ["100", "700"], tags(sample.fields(["100", "700"]))
  end

  def test_fields_by_range_and_regexp
    assert_equal ["650", "650"], tags(sample.fields("600".."699"))
    assert_equal ["852H", "856", "856"], tags(sample.fields(/\A85/))
  end

  def test_fields_with_four_character_tags
    assert_equal ["852H"], tags(sample.fields("852H"))
  end

  def test_fields_by_indicators
    assert_equal ["https://example.org/2"], sample.fields("856", ind2: "2").map { it["u"] }
    assert_equal 2, sample.fields("856", ind1: "4", ind2: ["0", "2"]).size
    assert_equal ["650"], tags(sample.fields(ind2: "7"))
  end

  def test_indicator_filters_never_match_control_fields
    assert_empty sample.fields("001", ind1: " ")
  end

  def test_rejects_invalid_tag_matchers
    assert_raises(ArgumentError) { sample.fields(245) }
    assert_raises(ArgumentError) { sample.fields(600..699) }
  end

  def test_rejects_invalid_indicator_filters
    assert_raises(ArgumentError) { sample.fields("856", ind1: :blank) }
  end

  def test_field_is_the_first_match
    assert_equal "Metadata", sample.field("650")["a"]
    assert_nil sample.field("999")
  end

  def test_brackets_find_a_field_by_tag
    assert_equal "123", sample["001"].value
    assert_equal "ger", sample["008"][35..37]
  end

  def test_values_of_data_fields
    assert_equal ["Title", "Subtitle"], sample.values("245")
    assert_equal ["Metadata"], sample.values("650", "a", ind2: "7")
    assert_equal ["Doe, Jane", "Roe, Richard"], sample.values(["100", "700"], "a")
  end

  def test_values_of_control_fields_only_without_codes
    assert_equal ["123"], sample.values("001")
    assert_empty sample.values("001", "a")
  end

  def test_value_is_the_first_value
    assert_equal "Subtitle", sample.value("245", "b")
    assert_equal "available", sample.value("852H", "as")
    assert_nil sample.value("999")
  end

  def test_add_inserts_by_tag
    record = sample
    record.add(DataField.new("500", " ", " ", [["a", "Note"]]))
    record.add(ControlField.new("003", "DE-1"))

    assert_equal ["001", "003", "008", "100", "245", "500", "650"], tags(record.fields).first(7)
  end

  def test_add_appends_a_tag_that_sorts_last
    record = sample
    result = record.add(DataField.new("999"))

    assert_same record, result
    assert_equal "999", record.fields.last.tag
  end

  def test_append_adds_at_the_end
    record = sample
    result = record.append(ControlField.new("005", "x"))

    assert_same record, result
    assert_equal "005", record.fields.last.tag
  end

  def test_add_and_append_reject_other_objects
    assert_raises(ArgumentError) { sample.add("500") }
    assert_raises(ArgumentError) { sample.append(nil) }
  end

  def test_remove_returns_the_removed_fields
    record = sample
    removed = record.remove("856", ind2: "2")

    assert_equal ["https://example.org/2"], removed.map { it["u"] }
    assert_equal ["https://example.org/1"], record.values("856", "u")
  end

  def test_remove_without_arguments_removes_all_fields
    record = sample
    record.remove

    assert_empty record.fields
  end

  def test_equality
    assert_equal sample, sample
    assert_equal sample.hash, sample.hash
    refute_equal sample, Record.new(leader: sample.leader, fields: sample.fields)
  end

  def test_dup_is_deep
    original = sample
    copy = original.dup
    copy.fields.first.value << "4"
    copy.field("245").add("c", "x")
    copy.leader << "!"

    assert_equal "123", original["001"].value
    assert_equal ["a", "b"], original["245"].subfields.map(&:code)
    assert_equal "00000nam a2200000 c 4500", original.leader
  end

  def test_to_h_is_marc_in_json
    record = Record.new(leader: "L", fields: [ControlField.new("001", "1"), DataField.new("245", "1", "0", [["a", "T"]])])
    expected = {
      "leader" => "L",
      "fields" => [{"001" => "1"}, {"245" => {"ind1" => "1", "ind2" => "0", "subfields" => [{"a" => "T"}]}}]
    }

    assert_equal expected, record.to_h
  end

  def test_to_h_without_a_leader
    assert_equal({"fields" => []}, Record.new.to_h)
  end

  def test_text_form
    record = Record.new(leader: "L", fields: [ControlField.new("001", "1"), DataField.new("245", "1", " ", [["a", "T"]])])

    assert_equal "=LDR  L\n=001  1\n=245  1\\$aT", record.to_s
    assert_equal "#<Metacrunch::Marcxml::Record\n=LDR  L\n=001  1\n=245  1\\$aT>", record.inspect
  end

end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/record_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Marcxml::Record`.

- [ ] **Step 3: Write the implementation**

`lib/metacrunch/marcxml/filter.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Selects fields by tag matchers and indicator filters (see Record).
    # Internal.
    class Filter

      def initialize(tags, ind1, ind2)
        @any_tag = tags.empty?
        @strings = []
        @patterns = []
        tags.each { add(it) }
        @ind1 = indicator(ind1, "ind1")
        @ind2 = indicator(ind2, "ind2")
      end

      def match?(field) = tag?(field.tag) && indicators?(field)

      private

      def add(tag)
        case tag
        when String then @strings << tag
        when Array then tag.each { add(it) }
        when Range then @strings.concat(range(tag))
        when Regexp then @patterns << tag
        else raise ArgumentError, "a tag must be a String, an Array, a Range or a Regexp, got #{tag.inspect}"
        end
      end

      def range(range)
        return range.to_a if range.begin.is_a?(String) && range.end.is_a?(String)

        raise ArgumentError, "a tag range must have String ends, got #{range.inspect}"
      end

      def indicator(filter, name)
        return filter if filter.nil? || filter.is_a?(String)
        return filter if filter.is_a?(Array) && filter.all?(String)

        raise ArgumentError, "#{name} must be nil, a String or an Array of Strings, got #{filter.inspect}"
      end

      def tag?(tag)
        @any_tag || @strings.include?(tag) || (!tag.nil? && @patterns.any? { it.match?(tag) })
      end

      def indicators?(field)
        return true if @ind1.nil? && @ind2.nil?
        return false unless field.is_a?(DataField)

        indicator?(@ind1, field.ind1) && indicator?(@ind2, field.ind2)
      end

      def indicator?(filter, value)
        return true if filter.nil?

        filter.is_a?(String) ? filter == value : filter.include?(value)
      end

    end
  end
end
```

`lib/metacrunch/marcxml/record.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A MARC record: a leader (a String or nil), the type attribute of
    # <record> (e.g. "Bibliographic") or nil, and an ordered Array of
    # ControlFields and DataFields.
    #
    # Tag matchers select fields by tag: a String (equal), an Array of
    # matchers (any), a Range of Strings (its members) or a Regexp.
    # Indicator filters (ind1:, ind2:) are nil (any), a String or an Array of
    # Strings; with an indicator filter, control fields never match.
    class Record

      attr_accessor :leader, :type

      def initialize(leader: nil, fields: [], type: nil)
        @leader = leader
        @type = type
        @fields = fields.map { check_field(it) }
      end

      # Without arguments the record's own Array (changes affect the
      # record), otherwise a new Array of the matching fields, in record
      # order.
      def fields(*tags, ind1: nil, ind2: nil)
        return @fields if tags.empty? && ind1.nil? && ind2.nil?

        filter = Filter.new(tags, ind1, ind2)
        @fields.select { filter.match?(it) }
      end

      # The first matching field, or nil.
      def field(*tags, ind1: nil, ind2: nil)
        filter = Filter.new(tags, ind1, ind2)
        @fields.find { filter.match?(it) }
      end

      def [](tag) = field(tag)

      # The values of the matching fields, in record order: of data fields
      # those of these codes (all without codes), of control fields their
      # value when no codes are given.
      def values(tags, *codes, ind1: nil, ind2: nil)
        fields(tags, ind1:, ind2:).flat_map do |field|
          if field.is_a?(DataField)
            field.values(*codes)
          else
            codes.empty? ? [field.value] : []
          end
        end
      end

      # The first of those values, or nil.
      def value(tags, *codes, ind1: nil, ind2: nil) = values(tags, *codes, ind1:, ind2:).first

      # Inserts the field before the first field whose tag sorts after its
      # tag (String#<=>), else at the end. Returns self.
      def add(field)
        check_field(field)
        index = @fields.index { (it.tag <=> field.tag) == 1 }
        index ? @fields.insert(index, field) : @fields.push(field)
        self
      end

      # Appends the field. Returns self.
      def append(field)
        @fields << check_field(field)
        self
      end

      # Removes the matching fields (all fields without arguments). Returns
      # them.
      def remove(*tags, ind1: nil, ind2: nil)
        filter = Filter.new(tags, ind1, ind2)
        removed = []
        @fields.reject! do |field|
          match = filter.match?(field)
          removed << field if match
          match
        end
        removed
      end

      def ==(other)
        other.instance_of?(Record) && other.leader == leader && other.type == type && other.fields == fields
      end

      alias eql? ==

      def hash = [Record, leader, type, @fields].hash

      # MARC-in-JSON. "leader" only when the record has one; type is not
      # part of MARC-in-JSON.
      def to_h
        json = {}
        json["leader"] = leader if leader
        json["fields"] = @fields.map(&:to_h)
        json
      end

      # One line per field in the mnemonic form of MarcEdit, the leader as
      # "=LDR".
      def to_s
        lines = leader ? ["=LDR  #{leader}"] : []
        (lines + @fields.map(&:to_s)).join("\n")
      end

      def inspect = "#<#{self.class.name}\n#{self}>"

      private

      def initialize_copy(source)
        super
        @leader = source.leader&.dup
        @type = source.type&.dup
        @fields = source.fields.map(&:dup)
      end

      def check_field(field)
        return field if field.is_a?(ControlField) || field.is_a?(DataField)

        raise ArgumentError, "a field must be a ControlField or a DataField, got #{field.inspect}"
      end

    end
  end
end
```

In `lib/metacrunch/marcxml.rb`, append to the require lines:

```ruby
require_relative "marcxml/filter"
require_relative "marcxml/record"
```

- [ ] **Step 4: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add Record with field selection and changes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Parsing (`Marcxml.parse`, `Marcxml.each`)

**Files:**
- Create: `lib/metacrunch/marcxml/string_source.rb`, `lib/metacrunch/marcxml/parser.rb`, `test/support/fixtures.rb`, `test/fixtures/collection.xml`, `test/fixtures/prefixed.xml`, `test/fixtures/local.xml`, `test/fixtures/edge.xml`
- Modify: `lib/metacrunch/marcxml.rb` (requires, `NORMALIZATIONS`, `parse`, `each`, `check_normalize`), `docs/superpowers/specs/2026-10-12-marcxml-ng-design.md` (two amendments)
- Test: `test/unit/parse_test.rb`

**Interfaces:**
- Consumes: `Record`, `ControlField`, `DataField`, `Subfield` (Tasks 2-3), `ParseError` (Task 1).
- Produces:
  - `StringSource.new(string)` (internal) with `#readpartial(length, buffer = nil)` returning binary chunks, `EOFError` at the end.
  - `Parser.run(input, normalize:, &block)` (internal).
  - `Marcxml::NORMALIZATIONS = [nil, :nfc]`, `Marcxml.parse(xml, normalize: nil)` → `Record`, `Marcxml.each(input, normalize: nil) { |record| }` → nil / Enumerator, `Marcxml.check_normalize(normalize)` (raises `ArgumentError`), private `check_input`.
  - Test helper module `Fixtures` with `fixture_path(name)` and `fixture(name)`.

- [ ] **Step 1: Amend the spec**

In `docs/superpowers/specs/2026-10-12-marcxml-ng-design.md`, section 4.2, replace

```
- A missing `ind1` or `ind2` attribute becomes `" "`; a missing `tag` or
  `code` becomes `""`. The `type` attribute of `<record>` is kept.
```

with

```
- A missing or empty `ind1` or `ind2` attribute becomes `" "`; a missing
  `tag` or `code` becomes `""`. The `type` attribute of `<record>` is kept.
- Values are UTF-8 (MARCXML is UTF-8); other encodings are not converted.
```

and in section 4.3, after `- Input that ends inside a record.` add

```
- A value that is not valid UTF-8, named by its field (`field 245 $a:
  invalid UTF-8`).
- Several records without a `<collection>` around them (not well-formed
  XML); `each_xml` and the `Reader` still read them.
```

- [ ] **Step 2: Write the fixtures and the fixture helper**

`test/support/fixtures.rb`:

```ruby
# frozen_string_literal: true

# Paths and contents of test/fixtures.
module Fixtures

  DIR = File.expand_path("../fixtures", __dir__)

  def fixture_path(name) = File.join(DIR, name)

  def fixture(name) = File.read(fixture_path(name), encoding: "UTF-8")

end
```

`test/fixtures/collection.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<collection xmlns="http://www.loc.gov/MARC21/slim">
  <record type="Bibliographic">
    <leader>00000nam a2200000 c 4500</leader>
    <controlfield tag="001">book-1</controlfield>
    <controlfield tag="008">200101s2020    gw            000 0 eng d</controlfield>
    <datafield tag="020" ind1=" " ind2=" ">
      <subfield code="a">9783000000001</subfield>
    </datafield>
    <datafield tag="100" ind1="1" ind2=" ">
      <subfield code="a">Doe, Jane</subfield>
      <subfield code="4">aut</subfield>
    </datafield>
    <datafield tag="245" ind1="1" ind2="0">
      <subfield code="a">Metadata in practice</subfield>
      <subfield code="b">a handbook</subfield>
      <subfield code="c">Jane Doe</subfield>
    </datafield>
    <datafield tag="264" ind1=" " ind2="1">
      <subfield code="a">Berlin</subfield>
      <subfield code="b">Example Press</subfield>
      <subfield code="c">2020</subfield>
    </datafield>
    <datafield tag="650" ind1=" " ind2="7">
      <subfield code="a">Metadata</subfield>
      <subfield code="2">gnd</subfield>
    </datafield>
  </record>
  <record type="Bibliographic">
    <leader>00000naa a2200000 c 4500</leader>
    <controlfield tag="001">article-1</controlfield>
    <datafield tag="245" ind1="0" ind2="0">
      <subfield code="a">Linked data for libraries</subfield>
    </datafield>
    <datafield tag="773" ind1="0" ind2="8">
      <subfield code="t">Journal of Examples</subfield>
      <subfield code="g">12 (2021), 3, p. 45-67</subfield>
    </datafield>
    <datafield tag="856" ind1="4" ind2="0">
      <subfield code="u">https://example.org/article-1</subfield>
    </datafield>
    <datafield tag="856" ind1="4" ind2="2">
      <subfield code="u">https://example.org/article-1/cover.jpg</subfield>
      <subfield code="3">Cover</subfield>
    </datafield>
  </record>
  <record type="Holdings">
    <leader>00000nx  a2200000un 4500</leader>
    <controlfield tag="001">holding-1</controlfield>
    <datafield tag="852" ind1="8" ind2=" ">
      <subfield code="b">MAIN</subfield>
      <subfield code="h">QA 76.9 .D3</subfield>
    </datafield>
  </record>
</collection>
```

`test/fixtures/prefixed.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim">
  <marc:record>
    <marc:leader>00000nam a2200000 c 4500</marc:leader>
    <marc:controlfield tag="001">prefixed-1</marc:controlfield>
    <marc:datafield tag="245" ind1="0" ind2="0">
      <marc:subfield code="a">First</marc:subfield>
    </marc:datafield>
  </marc:record>
  <marc:record>
    <marc:controlfield tag="001">prefixed-2</marc:controlfield>
  </marc:record>
</marc:collection>
```

`test/fixtures/local.xml` (one line, no XML declaration, no namespace, the leader after a control field, local tags and codes):

```xml
<collection><record><controlfield tag="001">local-1</controlfield><leader>00000nam a2200000 c 4500</leader><datafield tag="245" ind1="0" ind2="0"><subfield code="a">Local data</subfield></datafield><datafield tag="852H" ind1="8" ind2=" "><subfield code="b">MAIN</subfield><subfield code="as">available</subfield></datafield><datafield tag="AVA" ind1=" " ind2=" "><subfield code="dl">https://example.org/local-1</subfield></datafield></record></collection>
```

`test/fixtures/edge.xml` (keep the two spaces at the start and end of `  Two  spaces  ` and the line break inside the `b` subfield exactly):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<collection xmlns="http://www.loc.gov/MARC21/slim">
  <record type="Bibliographic">
    <controlfield tag="007">cr</controlfield>
    <controlfield tag="007">tu</controlfield>
    <datafield tag="245" ind1="1" ind2="0">
      <subfield code="a">  Two  spaces  </subfield>
      <subfield code="b">Line one
line two</subfield>
      <subfield code="a">Second a</subfield>
    </datafield>
    <datafield tag="500">
      <subfield code="a"><![CDATA[Tom & Jerry <3]]></subfield>
      <subfield code="b">split<!-- a comment -->value</subfield>
      <subfield code="c">&amp; &lt; &gt; &quot; &#xE9;</subfield>
      <subfield code="d"></subfield>
    </datafield>
  </record>
</collection>
```

- [ ] **Step 3: Write the failing test**

`test/unit/parse_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ParseTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml
  DataField = Metacrunch::Marcxml::DataField

  def ids(records) = records.map { it["001"].value }

  def edge = Marcxml.parse(fixture("edge.xml"))

  def test_each_yields_every_record_of_a_collection
    records = File.open(fixture_path("collection.xml")) { Marcxml.each(it).to_a }

    assert_equal ["book-1", "article-1", "holding-1"], ids(records)
    assert_equal ["Bibliographic", "Bibliographic", "Holdings"], records.map(&:type)
  end

  def test_reads_leader_fields_and_subfields_in_order
    book = Marcxml.each(fixture("collection.xml")).first
    title = DataField.new("245", "1", "0", [["a", "Metadata in practice"], ["b", "a handbook"], ["c", "Jane Doe"]])

    assert_equal "00000nam a2200000 c 4500", book.leader
    assert_equal ["001", "008", "020", "100", "245", "264", "650"], book.fields.map(&:tag)
    assert_equal title, book["245"]
  end

  def test_keeps_whitespace_and_line_breaks
    assert_equal ["  Two  spaces  ", "Line one\nline two", "Second a"], edge["245"].values
  end

  def test_keeps_subfield_order_and_repeated_control_fields
    assert_equal ["a", "b", "a"], edge["245"].subfields.map(&:code)
    assert_equal ["cr", "tu"], edge.values("007")
  end

  def test_reads_cdata_comments_entities_and_empty_values
    assert_equal ["Tom & Jerry <3", "splitvalue", "& < > \" é", ""], edge["500"].values
  end

  def test_missing_and_empty_indicators_are_blank
    empty = Marcxml.parse(%(<record><datafield tag="500" ind1="" ind2=""/></record>))["500"]

    assert_equal [" ", " "], [edge["500"].ind1, edge["500"].ind2]
    assert_equal [" ", " "], [empty.ind1, empty.ind2]
  end

  def test_prefixed_elements
    records = Marcxml.each(fixture("prefixed.xml")).to_a

    assert_equal ["prefixed-1", "prefixed-2"], ids(records)
    assert_equal "First", records.first.value("245", "a")
  end

  def test_leader_after_control_fields_and_local_tags
    record = Marcxml.parse(fixture("local.xml"))

    assert_equal "00000nam a2200000 c 4500", record.leader
    assert_equal "available", record.value("852H", "as")
    assert_equal "https://example.org/local-1", record.value("AVA", "dl")
  end

  def test_empty_records
    assert_equal Marcxml::Record.new, Marcxml.parse("<record></record>")
    assert_equal Marcxml::Record.new, Marcxml.parse("<record/>")
  end

  def test_ignores_unknown_elements
    xml = %(<wrapper><record><datafield tag="500"><subfield code="a">x<b>y</b>z</subfield></datafield></record></wrapper>)

    assert_equal "xz", Marcxml.parse(xml).value("500", "a")
  end

  def test_reads_strings_files_stringios_gzip_and_pipes
    xml = fixture("collection.xml")
    expected = Marcxml.each(xml).to_a
    reader, writer = IO.pipe
    Thread.new do
      writer.write(xml)
      writer.close
    end
    inputs = [File.open(fixture_path("collection.xml")), StringIO.new(xml),
              Zlib::GzipReader.new(StringIO.new(Zlib.gzip(xml))), reader]

    inputs.each { assert_equal expected, Marcxml.each(it).to_a }
  ensure
    inputs&.each(&:close)
  end

  def test_values_are_utf8_without_an_xml_declaration
    value = Marcxml.parse(%(<record><controlfield tag="001">Müller</controlfield></record>))["001"].value

    assert_equal Encoding::UTF_8, value.encoding
    assert_equal "Müller", value
  end

  def test_reads_input_with_a_byte_order_mark
    record = Marcxml.parse(%(﻿<record><controlfield tag="001">x</controlfield></record>))

    assert_equal "x", record["001"].value
  end

  def test_line_breaks_are_normalized_as_xml_demands
    xml = %(<record><datafield tag="500"><subfield code="a">a\r\nb</subfield></datafield></record>)

    assert_equal "a\nb", Marcxml.parse(xml).value("500", "a")
  end

  def test_normalize_nfc
    xml = %(<record><controlfield tag="001">Müller</controlfield></record>)

    assert_equal "Müller", Marcxml.parse(xml)["001"].value
    assert_equal "Müller", Marcxml.parse(xml, normalize: :nfc)["001"].value
  end

  def test_rejects_unknown_normalizations
    assert_raises(ArgumentError) { Marcxml.parse("<record/>", normalize: :nfd) }
  end

  def test_syntax_errors_name_line_and_column
    xml = %(<record>\n<datafield tag="245">\n<subfield code="a">x</datafield>\n</record>)
    error = assert_raises(Marcxml::ParseError) { Marcxml.parse(xml) }

    assert_match(/Start End Mismatch/, error.message)
    assert_equal [3, 21], [error.line, error.column]
  end

  def test_input_that_ends_inside_a_record
    assert_raises(Marcxml::ParseError) { Marcxml.parse(%(<record><datafield tag="245"><subfield code="a">x)) }
  end

  def test_invalid_entities
    xml = %(<record><controlfield tag="001">a &foo; b</controlfield></record>)

    assert_raises(Marcxml::ParseError) { Marcxml.parse(xml) }
  end

  def test_values_that_are_not_utf8
    xml = "<record><datafield tag=\"245\"><subfield code=\"a\">M\xFCller</subfield></datafield></record>".b
    error = assert_raises(Marcxml::ParseError) { Marcxml.parse(xml) }

    assert_equal "field 245 $a: invalid UTF-8", error.message
  end

  def test_bare_records_need_a_collection
    assert_raises(Marcxml::ParseError) { Marcxml.each("<record/><record/>").to_a }
  end

  def test_parse_needs_exactly_one_record
    assert_raises(Marcxml::ParseError) { Marcxml.parse("<collection/>") }
    error = assert_raises(Marcxml::ParseError) { Marcxml.parse(fixture("collection.xml")) }

    assert_match(/3 records found/, error.message)
  end

  def test_parse_needs_a_string
    assert_raises(ArgumentError) { Marcxml.parse(StringIO.new("<record/>")) }
  end

  def test_each_without_a_block_is_an_enumerator
    assert_instance_of Enumerator, Marcxml.each("<record/>")
  end

  def test_each_needs_a_string_or_an_io
    assert_raises(ArgumentError) { Marcxml.each(42) { nil } }
  end

end
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/parse_test.rb`
Expected: FAIL with `undefined method 'parse' for module Metacrunch::Marcxml` (and `each`).

- [ ] **Step 5: Write the implementation**

`lib/metacrunch/marcxml/string_source.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Reads a String in chunks through readpartial. Ox SAX is slow on a
    # String or a StringIO (superlinear in its size) but fast on objects
    # with readpartial; the splitter reads it the same way. Internal.
    class StringSource

      def initialize(string)
        @string = string
        @position = 0
      end

      # A binary chunk of at most length bytes; EOFError at the end, as
      # IO#readpartial.
      def readpartial(length, buffer = nil)
        raise EOFError, "end of string reached" if @position >= @string.bytesize

        chunk = @string.byteslice(@position, length).force_encoding(Encoding::BINARY)
        @position += chunk.bytesize
        buffer ? buffer.replace(chunk) : chunk
      end

    end
  end
end
```

`lib/metacrunch/marcxml/parser.rb`:

```ruby
# frozen_string_literal: true

require "ox"

module Metacrunch
  module Marcxml
    # The Ox SAX handler behind Marcxml.each: builds a Record per <record>
    # element and passes it to the block. Elements are matched by their
    # local name, so prefixes do not matter; other elements are ignored, and
    # inside a value their text too. Text is kept exactly (skip: :skip_none);
    # text and CDATA events are appended. Internal.
    class Parser < Ox::Sax

      OPTIONS = {skip: :skip_none, convert_special: true, smart: false}.freeze

      # Parses input (an object with readpartial or read) and passes each
      # Record to block. normalize: nil or :nfc.
      def self.run(input, normalize:, &block)
        parser = new(normalize, block)
        Ox.sax_parse(parser, input, **OPTIONS)
        parser.finish
      end

      def initialize(normalize, block)
        super()
        @normalize = normalize
        @block = block
        @names = {}
        @record = nil
        @field = nil
        @text = nil
        @kind = nil
        @skip = 0
        @target = nil
        @tag = nil
        @code = nil
      end

      def start_element(name)
        @target = nil
        return @skip += 1 if @text

        case local(name)
        when :record then start_record
        when :datafield then start_data_field if @record
        when :leader, :controlfield then start_value(local(name)) if @record
        when :subfield then start_value(:subfield) if @field
        end
      end

      def attr(name, value)
        case @target
        when :record then @record.type = utf8(value) if name == :type
        when :datafield then data_field_attr(name, value)
        when :controlfield then @tag = utf8(value) if name == :tag
        when :subfield then @code = utf8(value) if name == :code
        end
      end

      def text(value)
        @text << utf8(value) if @text && @skip.zero?
      end

      alias cdata text

      def end_element(name)
        @target = nil
        if @text
          return @skip -= 1 if @skip.positive?

          return finish_value
        end

        case local(name)
        when :datafield then finish_data_field if @field
        when :record then finish_record if @record
        end
      end

      # Ox reports here what is not well-formed.
      def error(message, line, column)
        raise ParseError.new(message, line:, column:)
      end

      # Raises if the input ended inside a record.
      def finish
        raise ParseError, "the input ended inside a record" if @record
      end

      private

      def local(name)
        @names[name] ||= begin
          text = name.name
          index = text.index(":")
          index ? text[(index + 1)..].to_sym : name
        end
      end

      def start_record
        @record = Record.new
        @field = nil
        @target = :record
      end

      def start_data_field
        @field = DataField.new("")
        @target = :datafield
      end

      def data_field_attr(name, value)
        case name
        when :tag then @field.tag = utf8(value)
        when :ind1 then @field.ind1 = indicator(value)
        when :ind2 then @field.ind2 = indicator(value)
        end
      end

      def start_value(kind)
        @kind = kind
        @text = String.new(encoding: Encoding::UTF_8)
        @tag = ""
        @code = ""
        @target = kind
      end

      def finish_value
        value = checked(@text)
        case @kind
        when :leader then @record.leader = value
        when :controlfield then @record.fields << ControlField.new(@tag, value)
        else @field.subfields << Subfield.new(@code, value)
        end
        @text = nil
        @kind = nil
      end

      def finish_data_field
        @record.fields << @field
        @field = nil
      end

      def finish_record
        record = @record
        @record = nil
        @field = nil
        @block.call(record)
      end

      # An empty indicator attribute is blank.
      def indicator(value) = value.empty? ? DataField::BLANK : utf8(value)

      # Ox returns binary strings for input without an XML declaration.
      def utf8(value) = value.force_encoding(Encoding::UTF_8)

      def checked(value)
        raise ParseError, "#{value_name}: invalid UTF-8" unless value.valid_encoding?
        return value if @normalize.nil? || value.ascii_only?

        value.unicode_normalize(:nfc)
      end

      def value_name
        case @kind
        when :leader then "leader"
        when :controlfield then "field #{@tag}"
        else "field #{@field.tag} $#{@code}"
        end
      end

    end
  end
end
```

`lib/metacrunch/marcxml.rb` (whole file):

```ruby
# frozen_string_literal: true

require_relative "marcxml/version"
require_relative "marcxml/errors"
require_relative "marcxml/subfield"
require_relative "marcxml/control_field"
require_relative "marcxml/data_field"
require_relative "marcxml/filter"
require_relative "marcxml/record"
require_relative "marcxml/string_source"
require_relative "marcxml/parser"

module Metacrunch
  # MARCXML for metacrunch: an ordered record model (Record, ControlField,
  # DataField, Subfield), a parser, a serializer, and a source (Reader) and
  # a sink (Writer). Only Reader and Writer depend on metacrunch.
  module Marcxml

    # The namespace of the MARC 21 XML schema.
    NAMESPACE = "http://www.loc.gov/MARC21/slim"

    # The values of normalize:.
    NORMALIZATIONS = [nil, :nfc].freeze

    class << self

      # The one record in xml, a String with one <record>, bare or in a
      # <collection>. Raises ParseError for none or more than one.
      def parse(xml, normalize: nil)
        raise ArgumentError, "xml must be a String, got #{xml.class}" unless xml.is_a?(String)

        records = each(xml, normalize:).to_a
        raise ParseError, "no record found" if records.empty?
        raise ParseError, "#{records.size} records found where one was expected (use Marcxml.each)" if records.size > 1

        records.first
      end

      # Yields every record of input: a String, or an object with
      # readpartial or read (a File, a Zlib::GzipReader, a pipe). Without a
      # block an Enumerator.
      def each(input, normalize: nil, &block)
        check_input(input)
        check_normalize(normalize)
        return enum_for(:each, input, normalize:) unless block

        Parser.run(input.is_a?(String) ? StringSource.new(input) : input, normalize:, &block)
        nil
      end

      # Raises ArgumentError unless normalize is nil or :nfc.
      def check_normalize(normalize)
        return if NORMALIZATIONS.include?(normalize)

        raise ArgumentError, "normalize must be nil or :nfc, got #{normalize.inspect}"
      end

      private

      def check_input(input)
        return if input.is_a?(String) || input.respond_to?(:readpartial) || input.respond_to?(:read)

        raise ArgumentError, "input must be a String or respond to #readpartial or #read, got #{input.class}"
      end

    end

  end
end
```

- [ ] **Step 6: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no offenses. If Ox reports a different line or column in `test_syntax_errors_name_line_and_column`, keep the assertion on what Ox reports for this input (it reported line 3, column 21 when the plan was written) and make sure both are Integers.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Parse MARCXML with Ox SAX" -m "Keeps whitespace, CDATA, comments-split values, prefixes, field and subfield order; values must be UTF-8. Strings are read through readpartial, because Ox is superlinear on Strings." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Splitting (`Marcxml.each_xml`)

**Files:**
- Create: `lib/metacrunch/marcxml/splitter.rb`
- Modify: `lib/metacrunch/marcxml.rb` (require, `each_xml`)
- Test: `test/unit/each_xml_test.rb`

**Interfaces:**
- Consumes: `StringSource` (Task 4), `check_input` (Task 4).
- Produces: `Splitter.new(input)` (internal) with `#each { |xml| }`; `Marcxml.each_xml(input) { |xml| }` → nil / Enumerator; yielded Strings are UTF-8, from the start tag to the end tag.

- [ ] **Step 1: Write the failing test**

`test/unit/each_xml_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EachXmlTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml

  # Gives the input one byte per call, to cut every tag.
  class Trickle

    def initialize(string)
      @bytes = string.b
      @position = 0
    end

    def readpartial(_length)
      raise EOFError if @position >= @bytes.bytesize

      @position += 1
      @bytes.byteslice(@position - 1, 1)
    end

  end

  # Has only read, as some IO-like objects do.
  class ReadOnly

    def initialize(string)
      @io = StringIO.new(string)
    end

    def read(length) = @io.read(length)

  end

  def test_cuts_a_collection_into_records
    xmls = Marcxml.each_xml(fixture("collection.xml")).to_a

    assert_equal 3, xmls.size
    assert(xmls.all? { it.start_with?("<record") && it.end_with?("</record>") })
    assert_equal Marcxml.each(fixture("collection.xml")).to_a, xmls.map { Marcxml.parse(it) }
  end

  def test_a_bare_record
    xml = %(<record><controlfield tag="001">1</controlfield></record>)

    assert_equal [xml], Marcxml.each_xml(xml).to_a
  end

  def test_prefixed_records
    xmls = Marcxml.each_xml(fixture("prefixed.xml")).to_a

    assert_equal 2, xmls.size
    assert(xmls.all? { it.start_with?("<marc:record>") && it.end_with?("</marc:record>") })
  end

  def test_skips_text_between_records
    xml = %(<?xml version="1.0"?>\n<collection>\n<!-- one -->\n<record>1</record>\n\n<record>2</record>\n</collection>\n)

    assert_equal ["<record>1</record>", "<record>2</record>"], Marcxml.each_xml(xml).to_a
  end

  def test_input_without_records
    assert_empty Marcxml.each_xml("").to_a
    assert_empty Marcxml.each_xml("<collection/>").to_a
  end

  def test_elements_that_only_start_with_record_are_not_records
    assert_equal ["<record>x</record>"], Marcxml.each_xml("<records><record>x</record></records>").to_a
  end

  def test_empty_and_self_closing_records
    xml = "<collection><record/><record></record><record>x</record></collection>"

    assert_equal ["<record/>", "<record></record>", "<record>x</record>"], Marcxml.each_xml(xml).to_a
  end

  def test_records_cut_by_chunk_boundaries
    xml = fixture("collection.xml")

    assert_equal Marcxml.each_xml(xml).to_a, Marcxml.each_xml(Trickle.new(xml)).to_a
  end

  def test_records_are_utf8
    xml = Marcxml.each_xml(Trickle.new("<record>Müller</record>")).first

    assert_equal Encoding::UTF_8, xml.encoding
    assert_equal "<record>Müller</record>", xml
  end

  def test_reads_inputs_with_only_read
    assert_equal 3, Marcxml.each_xml(ReadOnly.new(fixture("collection.xml"))).count
  end

  def test_concatenated_documents_and_bare_records
    assert_equal 6, Marcxml.each_xml(fixture("collection.xml") * 2).count
    assert_equal 2, Marcxml.each_xml("<record/><record/>").count
  end

  def test_needs_a_string_or_an_io
    assert_raises(ArgumentError) { Marcxml.each_xml(nil) { nil } }
  end

end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/each_xml_test.rb`
Expected: FAIL with `undefined method 'each_xml' for module Metacrunch::Marcxml`.

- [ ] **Step 3: Write the implementation**

`lib/metacrunch/marcxml/splitter.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Cuts MARCXML into record strings without parsing it (Marcxml.each_xml).
    # The record element name, with its prefix, is taken from the first
    # record start tag; a record runs from a start tag to the next matching
    # end tag. An end tag inside CDATA or a comment cuts a record there.
    # Internal.
    class Splitter

      CHUNK_SIZE = 65_536

      # Bytes kept while no start tag is found, for a tag cut by a chunk
      # boundary.
      KEEP = 256

      FIRST_START = %r{<(?:([A-Za-z_][\w.-]*):)?record[\s>/]}n

      SLASH = "/".ord

      def initialize(input)
        @input = input.is_a?(String) ? StringSource.new(input) : input
        @buffer = String.new(encoding: Encoding::BINARY)
        @position = 0
        @start = nil
        @end_tag = nil
      end

      def each
        loop do
          if (xml = take)
            yield xml
          elsif !fill
            break
          end
        end
      end

      private

      # The next whole record in the buffer, or nil.
      def take
        return unless detect

        first = @buffer.index(@start, @position)
        return skip unless first

        @position = first
        open_end = @buffer.index(">", first)
        return unless open_end
        return slice(first, open_end + 1) if @buffer.getbyte(open_end - 1) == SLASH

        close = @buffer.index(@end_tag, open_end)
        close && slice(first, close + @end_tag.bytesize)
      end

      # Finds the record element name in the first start tag; false until
      # it is in the buffer.
      def detect
        return true if @start

        match = FIRST_START.match(@buffer, @position)
        return skip && false unless match

        prefix = match[1] ? "#{match[1]}:" : ""
        @start = %r{<#{Regexp.escape(prefix)}record[\s>/]}n
        @end_tag = "</#{prefix}record>".b
        true
      end

      # Drops the buffer but its last bytes. Returns nil.
      def skip
        @position = [@position, @buffer.bytesize - KEEP].max
        nil
      end

      def slice(from, to)
        @position = to
        @buffer.byteslice(from, to - from).force_encoding(Encoding::UTF_8)
      end

      # Appends the next chunk, dropping what was taken; false at the end of
      # the input.
      def fill
        chunk = read
        return false unless chunk

        @buffer = @buffer.byteslice(@position..) << chunk.b
        @position = 0
        true
      end

      def read
        chunk = @input.respond_to?(:readpartial) ? @input.readpartial(CHUNK_SIZE) : @input.read(CHUNK_SIZE)
        chunk unless chunk.nil? || chunk.empty?
      rescue EOFError
        nil
      end

    end
  end
end
```

`return skip && false unless match` returns nil (falsy) because `skip` returns nil; if RuboCop objects, write it as two lines: `skip` then `return false`.

In `lib/metacrunch/marcxml.rb`, add `require_relative "marcxml/splitter"` after the parser require, and add this method after `each`:

```ruby
      # Yields every record of input as a String from its start tag to its
      # end tag, without parsing it. Without a block an Enumerator.
      def each_xml(input, &block)
        check_input(input)
        return enum_for(:each_xml, input) unless block

        Splitter.new(input).each(&block)
        nil
      end
```

- [ ] **Step 4: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Split MARCXML into record strings" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Serializing (`Record#to_xml`)

**Files:**
- Create: `lib/metacrunch/marcxml/serializer.rb`
- Modify: `lib/metacrunch/marcxml/record.rb` (`to_xml`), `lib/metacrunch/marcxml.rb` (require)
- Test: `test/unit/to_xml_test.rb`

**Interfaces:**
- Consumes: `Record`, fields (Tasks 2-3), `NAMESPACE`, `SerializeError` (Task 1), `Marcxml.parse`/`each` (Task 4).
- Produces: `Serializer.record(record, namespace:)` (internal); `Record#to_xml(namespace: true)` → String, one element per line, every line ending in `"\n"`, indented by 2 spaces per level.

- [ ] **Step 1: Write the failing test**

`test/unit/to_xml_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ToXmlTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml
  Record = Metacrunch::Marcxml::Record
  ControlField = Metacrunch::Marcxml::ControlField
  DataField = Metacrunch::Marcxml::DataField

  def sample
    Record.new(leader: "00000nam a2200000 c 4500", type: "Bibliographic",
               fields: [ControlField.new("001", "1"), DataField.new("245", "1", "0", [["a", "Title"], ["b", "Sub"]])])
  end

  def test_writes_marcxml
    expected = <<~XML
      <record xmlns="http://www.loc.gov/MARC21/slim" type="Bibliographic">
        <leader>00000nam a2200000 c 4500</leader>
        <controlfield tag="001">1</controlfield>
        <datafield tag="245" ind1="1" ind2="0">
          <subfield code="a">Title</subfield>
          <subfield code="b">Sub</subfield>
        </datafield>
      </record>
    XML

    assert_equal expected, sample.to_xml
  end

  def test_without_namespace_type_and_leader
    xml = Record.new(fields: [ControlField.new("001", "1")]).to_xml(namespace: false)

    assert_equal %(<record>\n  <controlfield tag="001">1</controlfield>\n</record>\n), xml
  end

  def test_escapes_text
    xml = Record.new(fields: [ControlField.new("001", %(a & b < c > d "e"))]).to_xml

    assert_includes xml, %(>a &amp; b &lt; c &gt; d "e"</controlfield>)
  end

  def test_escapes_attributes
    xml = Record.new(fields: [DataField.new(%(5"0), "&", "<", [["\t", "x"]])]).to_xml

    assert_includes xml, %(<datafield tag="5&quot;0" ind1="&amp;" ind2="&lt;">)
    assert_includes xml, %(<subfield code="&#9;">x</subfield>)
  end

  def test_tabs_and_line_breaks_in_text_are_kept
    record = Record.new(fields: [DataField.new("500", " ", " ", [["a", "a\tb\nc"]])])

    assert_includes record.to_xml, ">a\tb\nc<"
  end

  def test_carriage_returns_survive
    record = Record.new(fields: [DataField.new("500", " ", " ", [["a", "a\r\nb"]])])

    assert_includes record.to_xml, "a&#13;\nb"
    assert_equal record, Marcxml.parse(record.to_xml)
  end

  def test_nil_values_are_written_empty
    xml = Record.new(fields: [ControlField.new("001", nil)]).to_xml

    assert_includes xml, %(<controlfield tag="001"></controlfield>)
  end

  def test_rejects_characters_xml_cannot_represent
    ["\u0001", "\u000B", "\u001F", "￾", "￿"].each do |char|
      record = Record.new(fields: [DataField.new("245", "1", "0", [["a", "x#{char}y"]])])
      error = assert_raises(Marcxml::SerializeError) { record.to_xml }

      assert_match(/\Afield 245 \$a: /, error.message)
    end
  end

  def test_rejects_invalid_utf8
    record = Record.new(fields: [ControlField.new("001", "M\xFCller")])
    error = assert_raises(Marcxml::SerializeError) { record.to_xml }

    assert_match(/\Afield 001: invalid UTF-8/, error.message)
  end

  def test_round_trip_of_every_fixture
    ["collection.xml", "prefixed.xml", "local.xml", "edge.xml"].each do |name|
      Marcxml.each(fixture(name)) do |record|
        assert_equal record, Marcxml.parse(record.to_xml), name
      end
    end
  end

  def test_round_trip_of_tricky_values
    record = Record.new(
      leader: "00000nam a2200000 c 4500", type: "Bibliographic",
      fields: [
        ControlField.new("008", "  spaces at both ends  "),
        DataField.new("245", " ", " ", [["a", %(Quotes " and ' and <tags> & more)], ["b", "Ünïcödé"], ["c", ""]]),
        DataField.new("852H", "8", " ", [["as", "line\nbreak\tand tab\r"]])
      ]
    )

    assert_equal record, Marcxml.parse(record.to_xml)
  end

end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/to_xml_test.rb`
Expected: FAIL with `undefined method 'to_xml' for an instance of Metacrunch::Marcxml::Record`.

- [ ] **Step 3: Write the implementation**

`lib/metacrunch/marcxml/serializer.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Writes a Record as MARCXML (Record#to_xml): one element per line,
    # indented by two spaces per level. Internal.
    module Serializer

      # Characters XML 1.0 cannot represent, also not as references.
      FORBIDDEN = /[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]/

      TEXT = {"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\r" => "&#13;"}.freeze
      ATTRIBUTE = TEXT.merge("\"" => "&quot;", "\t" => "&#9;", "\n" => "&#10;").freeze

      module_function

      def record(record, namespace:)
        xml = +"<record"
        xml << " xmlns=\"#{NAMESPACE}\"" if namespace
        xml << " type=\"#{attribute(record.type, "type")}\"" if record.type
        xml << ">\n"
        xml << "  <leader>#{text(record.leader, "leader")}</leader>\n" if record.leader
        record.fields.each { field(xml, it) }
        xml << "</record>\n"
      end

      def field(xml, field)
        where = "field #{field.tag}"
        tag = attribute(field.tag, where)
        if field.is_a?(ControlField)
          xml << "  <controlfield tag=\"#{tag}\">#{text(field.value, where)}</controlfield>\n"
        else
          data_field(xml, field, tag, where)
        end
      end

      def data_field(xml, field, tag, where)
        xml << "  <datafield tag=\"#{tag}\" ind1=\"#{attribute(field.ind1, where)}\" " \
               "ind2=\"#{attribute(field.ind2, where)}\">\n"
        field.subfields.each do |subfield|
          at = "#{where} $#{subfield.code}"
          xml << "    <subfield code=\"#{attribute(subfield.code, at)}\">#{text(subfield.value, at)}</subfield>\n"
        end
        xml << "  </datafield>\n"
      end

      def text(value, where) = escape(value, where, /[&<>\r]/, TEXT)

      def attribute(value, where) = escape(value, where, /[&<>"\r\t\n]/, ATTRIBUTE)

      # nil is written as "". Raises SerializeError for invalid UTF-8 and
      # for characters XML 1.0 cannot represent.
      def escape(value, where, pattern, table)
        string = value.to_s
        string = string.dup.force_encoding(Encoding::UTF_8) unless string.encoding == Encoding::UTF_8
        raise SerializeError, "#{where}: invalid UTF-8 #{string.inspect}" unless string.valid_encoding?

        forbidden = string[FORBIDDEN]
        raise SerializeError, "#{where}: #{forbidden.inspect} cannot be represented in XML 1.0" if forbidden

        string.gsub(pattern, table)
      end

    end
  end
end
```

In `lib/metacrunch/marcxml/record.rb`, add after `to_h`:

```ruby
      # The record as MARCXML; namespace: false leaves out xmlns (a
      # <collection> declares it).
      def to_xml(namespace: true) = Serializer.record(self, namespace:)
```

In `lib/metacrunch/marcxml.rb`, add `require_relative "marcxml/serializer"` after the record require.

- [ ] **Step 4: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Write records as MARCXML" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Source `Metacrunch::Marcxml::Reader`

**Files:**
- Create: `lib/metacrunch/marcxml/reader.rb`
- Modify: `lib/metacrunch/marcxml.rb` (require)
- Test: `test/unit/reader_test.rb`

**Interfaces:**
- Consumes: `Marcxml.each_xml`, `Marcxml.parse`, `Marcxml.check_normalize`, `ParseError`; `Metacrunch::InvalidRecord` (`Data.define(:raw, :error)`) from metacrunch.
- Produces: `Reader.new(targets, parse: true, normalize: nil)`, `#each { |record_or_xml_or_invalid| }`, `#progress` → Float in 0.0..1.0 or nil; `Reader::STDIO = "-"`, `Reader::PROGRESS_EVERY = 256`.

- [ ] **Step 1: Write the failing test**

`test/unit/reader_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "rubygems/package"

class ReaderTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml
  Reader = Metacrunch::Marcxml::Reader
  IDS = ["book-1", "article-1", "holding-1"].freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_reads_records_from_a_path
    assert_equal IDS, ids(read(Reader.new(fixture_path("collection.xml"))))
  end

  def test_reads_pathnames_and_several_targets
    reader = Reader.new([Pathname(fixture_path("collection.xml")), fixture_path("local.xml")])

    assert_equal [*IDS, "local-1"], ids(read(reader))
  end

  def test_reads_stdin
    stdin = $stdin
    File.open(fixture_path("collection.xml")) do |file|
      $stdin = file

      assert_equal IDS, ids(read(Reader.new("-")))
    end
  ensure
    $stdin = stdin
  end

  def test_reads_an_io_and_leaves_it_open
    File.open(fixture_path("collection.xml")) do |file|
      assert_equal IDS, ids(read(Reader.new(file)))
      refute_predicate file, :closed?
    end
  end

  def test_reads_gzip_files
    path = write("records.xml.gz", Zlib.gzip(fixture("collection.xml")))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_reads_tar_archives
    archive = tar("a.xml" => fixture("collection.xml"), "b.xml" => fixture("local.xml"))
    paths = [write("records.tar", archive), write("records.tar.gz", Zlib.gzip(archive)),
             write("records.tgz", Zlib.gzip(archive))]

    paths.each { assert_equal [*IDS, "local-1"], ids(read(Reader.new(it))) }
  end

  def test_parse_false_yields_record_strings
    items = read(Reader.new(fixture_path("collection.xml"), parse: false))

    assert(items.all? { it.is_a?(String) && it.start_with?("<record") })
    assert_equal Marcxml.each(fixture("collection.xml")).to_a, items.map { Marcxml.parse(it) }
  end

  def test_a_broken_record_is_an_invalid_record
    xml = %(<collection><record><controlfield tag="001">1</controlfield></record>) +
          %(<record><controlfield tag="001">2</record>) +
          %(<record><controlfield tag="001">3</controlfield></record></collection>)
    items = read(Reader.new(write("broken.xml", xml)))

    assert_equal [Marcxml::Record, Metacrunch::InvalidRecord, Marcxml::Record], items.map(&:class)
    assert_equal %(<record><controlfield tag="001">2</record>), items[1].raw
    assert_instance_of Marcxml::ParseError, items[1].error
  end

  def test_values_that_are_not_utf8_make_an_invalid_record
    xml = "<collection><record><controlfield tag=\"001\">M\xFCller</controlfield></record></collection>".b

    assert_instance_of Metacrunch::InvalidRecord, read(Reader.new(write("latin1.xml", xml))).first
  end

  def test_concatenated_files_and_bare_records
    assert_equal 6, read(Reader.new(write("cat.xml", fixture("collection.xml") * 2))).size
    assert_equal 2, read(Reader.new(write("bare.xml", "<record/><record/>"))).size
  end

  def test_normalize
    path = write("nfd.xml", %(<record><controlfield tag="001">Müller</controlfield></record>))

    assert_equal "Müller", read(Reader.new(path, normalize: :nfc)).first["001"].value
  end

  def test_rejects_invalid_arguments
    assert_raises(ArgumentError) { Reader.new([]) }
    assert_raises(ArgumentError) { Reader.new(42) }
    assert_raises(ArgumentError) { Reader.new("a.xml", normalize: :nfd) }
  end

  def test_progress
    records = Array.new(600) { %(<record><controlfield tag="001">#{it}</controlfield></record>) }
    reader = Reader.new(write("many.xml", "<collection>#{records.join("\n")}</collection>"))
    progress = []
    reader.each { progress << reader.progress }

    assert_equal progress.sort, progress
    assert_in_delta 0.0, progress.first
    assert_in_delta 1.0, reader.progress
  end

  def test_no_progress_before_reading_and_for_ios
    File.open(fixture_path("collection.xml")) do |file|
      reader = Reader.new(file)
      read(reader)

      assert_nil Reader.new(fixture_path("collection.xml")).progress
      assert_nil reader.progress
    end
  end

  def test_closes_files_on_break_and_on_errors
    path = fixture_path("collection.xml")
    Reader.new(path).each { break }

    assert_raises(RuntimeError) { Reader.new(path).each { raise "stop" } }
    assert_empty(ObjectSpace.each_object(File).select { !it.closed? && it.path == path })
  end

  def test_missing_files_and_broken_gzip_raise
    assert_raises(Errno::ENOENT) { read(Reader.new(File.join(@dir, "missing.xml"))) }
    assert_raises(Zlib::GzipFile::Error) { read(Reader.new(write("broken.gz", "not gzip"))) }
  end

  private

  def read(reader)
    items = []
    reader.each { items << it }
    items
  end

  def ids(records) = records.map { it["001"].value }

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

  def tar(entries)
    io = StringIO.new
    Gem::Package::TarWriter.new(io) do |tar|
      tar.mkdir("data", 0o755)
      entries.each do |name, content|
        tar.add_file_simple("data/#{name}", 0o644, content.bytesize) { it.write(content) }
      end
    end
    io.string
  end

end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/reader_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Marcxml::Reader`.

- [ ] **Step 3: Write the implementation**

`lib/metacrunch/marcxml/reader.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch"
require "pathname"
require "rubygems/package"
require "zlib"

module Metacrunch
  module Marcxml
    # A metacrunch source: reads MARCXML from files (.xml, .gz, .tar,
    # .tar.gz, .tgz), stdin ("-") or IOs and yields a Record per record, or
    # with parse: false its XML string, which is cheaper to send to workers.
    # A record that cannot be parsed is yielded as Metacrunch::InvalidRecord.
    class Reader

      STDIO = "-"

      # How often (in records) the position in a file is sampled for
      # #progress.
      PROGRESS_EVERY = 256

      # targets: a path (String or Pathname), "-" for stdin, an IO, or an
      # Array of those. IOs are never closed.
      def initialize(targets, parse: true, normalize: nil)
        @targets = targets.is_a?(Array) ? targets : [targets]
        raise ArgumentError, "targets must not be empty" if @targets.empty?

        @targets.each { check_target(it) }
        Marcxml.check_normalize(normalize)
        @parse = parse
        @normalize = normalize
        @total = nil
        @done = 0
      end

      def each
        @total = total_size
        @done = 0
        finished = 0
        @targets.each do |target|
          with_input(target) do |input, file|
            count = 0
            each_document(input, target) do |document|
              Marcxml.each_xml(document) do |xml|
                count += 1
                @done = finished + file.pos if file && (count % PROGRESS_EVERY).zero?
                yield(@parse ? record(xml) : xml)
              end
            end
            finished += file.size if file
            @done = finished
          end
        end
      end

      # The share of the files read so far, from 0.0 to 1.0 (the compressed
      # position for gzip files); nil before reading and when a target is
      # stdin, an IO or not a regular file.
      def progress
        total = @total
        return unless total
        return 1.0 if total.zero?

        [@done.fdiv(total), 1.0].min
      end

      private

      def check_target(target)
        return if path?(target) || target == STDIO || target.respond_to?(:readpartial) || target.respond_to?(:read)

        raise ArgumentError, "a target must be a path, \"-\" or an IO, got #{target.inspect}"
      end

      def path?(target) = (target.is_a?(String) && target != STDIO) || target.is_a?(Pathname)

      # The size of all targets if all are regular files, else nil.
      def total_size
        @targets.sum do |target|
          return nil unless path?(target) && File.file?(target.to_s)

          File.size(target.to_s)
        end
      end

      # Yields the IO to read and the File for progress (nil for stdin,
      # IOs and files that are not regular). Files are closed in any case.
      def with_input(target)
        return yield($stdin, nil) if target == STDIO
        return yield(target, nil) unless path?(target)

        File.open(target.to_s, "rb") do |file|
          yield file, (file.stat.file? ? file : nil)
        end
      end

      # Yields each MARCXML document of input: input itself, its gzip
      # content, or each regular file of a tar archive.
      def each_document(input, target, &block)
        name = path?(target) ? target.to_s : ""
        if name.end_with?(".tar.gz", ".tgz")
          gunzip(input) { each_entry(it, &block) }
        elsif name.end_with?(".tar")
          each_entry(input, &block)
        elsif name.end_with?(".gz")
          gunzip(input, &block)
        else
          yield input
        end
      end

      def gunzip(io)
        gzip = Zlib::GzipReader.new(io)
        yield gzip
      ensure
        gzip&.finish
      end

      def each_entry(io)
        Gem::Package::TarReader.new(io).each { |entry| yield entry if entry.file? }
      end

      def record(xml)
        Marcxml.parse(xml, normalize: @normalize)
      rescue ParseError => e
        Metacrunch::InvalidRecord.new(raw: xml, error: e)
      end

    end
  end
end
```

In `lib/metacrunch/marcxml.rb`, add `require_relative "marcxml/reader"` as the last require.

- [ ] **Step 4: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add the MARCXML reader source" -m "Reads files, gzip files, tar archives, stdin and IOs; a record that cannot be parsed becomes an InvalidRecord; parse: false yields the XML for workers." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Sink `Metacrunch::Marcxml::Writer`

**Files:**
- Create: `lib/metacrunch/marcxml/writer.rb`
- Modify: `lib/metacrunch/marcxml.rb` (require)
- Test: `test/unit/writer_test.rb`

**Interfaces:**
- Consumes: `Record#to_xml(namespace: false)`, `SerializeError`, `NAMESPACE`; `Metacrunch::Error`, `Metacrunch::Context` (tests).
- Produces: `Writer.new(target)`, `#open(context)`, `#write(record, ctx)`, `#write_batch(records, ctxs)`, `#close`; `Writer::HEADER`, `Writer::FOOTER`.

- [ ] **Step 1: Write the failing test**

`test/unit/writer_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml
  Writer = Metacrunch::Marcxml::Writer
  HEADER = %(<?xml version="1.0" encoding="UTF-8"?>\n<collection xmlns="http://www.loc.gov/MARC21/slim">\n)

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  # A pipe that breaks when the buffered data is flushed at the end.
  class PipeClosedBeforeFlush < StringIO

    def flush = raise(Errno::EPIPE)

  end

  def setup
    @dir = Dir.mktmpdir
    @ctx = Metacrunch::Context.new(id: "1", position: 3, logger: Logger.new(nil))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_writes_a_collection
    io = StringIO.new
    writer = open_writer(io)
    writer.write(record, @ctx)
    writer.close
    expected = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <collection xmlns="http://www.loc.gov/MARC21/slim">
        <record>
          <controlfield tag="001">1</controlfield>
        </record>
      </collection>
    XML

    assert_equal expected, io.string
  end

  def test_write_batch
    io = StringIO.new
    writer = open_writer(io)
    writer.write_batch([record, record], [@ctx, @ctx])
    writer.close

    assert_equal 2, Marcxml.each(io.string).count
  end

  def test_an_empty_run_gives_an_empty_collection
    io = StringIO.new
    open_writer(io).close

    assert_equal "#{HEADER}</collection>\n", io.string
  end

  def test_writes_empty_records
    io = StringIO.new
    writer = open_writer(io)
    writer.write(Marcxml::Record.new, @ctx)
    writer.close

    assert_equal [Marcxml::Record.new], Marcxml.each(io.string).to_a
  end

  def test_writes_files_and_gzip_files
    records = Marcxml.each(fixture("collection.xml")).to_a
    ["out.xml", "out.xml.gz"].each do |name|
      path = File.join(@dir, name)
      writer = open_writer(path)
      records.each { writer.write(it, @ctx) }
      writer.close
      content = name.end_with?(".gz") ? Zlib.gunzip(File.binread(path)) : File.read(path)

      assert_equal records, Marcxml.each(content).to_a
    end
  end

  def test_writes_stdout_and_leaves_ios_open
    stdout = $stdout
    io = StringIO.new
    $stdout = io
    open_writer("-").close

    refute_predicate io, :closed?
    assert_equal "#{HEADER}</collection>\n", io.string
  ensure
    $stdout = stdout
  end

  def test_rejects_records_of_other_classes
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write({"001" => "1"}, @ctx) }

    assert_equal "record at position 3 is not a Metacrunch::Marcxml::Record (Hash)", error.message
  end

  def test_records_that_cannot_be_written
    writer = open_writer(StringIO.new)
    bad = Marcxml::Record.new(fields: [Marcxml::ControlField.new("001", "\u0001")])
    error = assert_raises(Metacrunch::Error) { writer.write(bad, @ctx) }

    assert_match(/\Arecord at position 3 cannot be written as MARCXML: field 001: /, error.message)
  end

  def test_a_closed_pipe_raises_sigpipe_once
    writer = Writer.new(ClosedPipe.new)
    error = assert_raises(SignalException) { writer.open(nil) }
    writer.write(record, @ctx)
    writer.close

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_a_pipe_closed_before_the_final_flush_raises_sigpipe
    writer = open_writer(PipeClosedBeforeFlush.new)
    writer.write(record, @ctx)

    assert_raises(SignalException) { writer.close }
  end

  private

  def record = Marcxml::Record.new(fields: [Marcxml::ControlField.new("001", "1")])

  def open_writer(target)
    writer = Writer.new(target)
    writer.open(nil)
    writer
  end

end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/writer_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Marcxml::Writer`.

- [ ] **Step 3: Write the implementation**

`lib/metacrunch/marcxml/writer.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch"
require "zlib"

module Metacrunch
  module Marcxml
    # A metacrunch sink: writes Records as one MARCXML <collection> to a
    # file (.gz compressed), stdout ("-") or an IO. close writes the end of
    # the collection, also after an aborted run, so the output stays
    # well-formed.
    class Writer

      STDIO = "-"
      GZIP = ".gz"
      HEADER = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<collection xmlns=\"#{NAMESPACE}\">\n".freeze
      FOOTER = "</collection>\n"

      def initialize(target)
        @target = target.is_a?(Pathname) ? target.to_s : target
        @io = nil
        @own = false
        @broken = false
      end

      def open(_context)
        @io, @own = output
        emit(HEADER)
      end

      def write(record, ctx)
        emit(xml(record, ctx))
      end

      def write_batch(records, ctxs)
        emit(records.zip(ctxs).map { |record, ctx| xml(record, ctx) }.join)
      end

      def close
        io = @io
        @io = nil
        return unless io

        guard { io.write(FOOTER) }
        guard { @own ? io.close : io.flush }
      ensure
        discard(io) if @own && io && !io.closed?
      end

      private

      def xml(record, ctx)
        unless record.is_a?(Record)
          raise Metacrunch::Error,
                "record at position #{ctx.position} is not a Metacrunch::Marcxml::Record (#{record.class})"
        end

        record.to_xml(namespace: false).each_line.map { "  #{it}" }.join
      rescue SerializeError => e
        raise Metacrunch::Error, "record at position #{ctx.position} cannot be written as MARCXML: #{e.message}"
      end

      def emit(text)
        guard { @io.write(text) }
      end

      # Turns EPIPE into SIGPIPE, once; afterwards nothing is written.
      def guard
        return if @broken

        yield
      rescue Errno::EPIPE
        @broken = true
        raise SignalException, "PIPE"
      end

      # Closes a file after a broken pipe; its buffer can no longer be
      # written.
      def discard(io)
        io.close
      rescue Errno::EPIPE
        nil
      end

      # [io, own]: own IOs are closed, IOs from outside only flushed.
      def output
        return [$stdout, false] if @target == STDIO
        return [@target, false] unless @target.is_a?(String)
        return [Zlib::GzipWriter.open(@target), true] if @target.end_with?(GZIP)

        [File.open(@target, "w"), true]
      end

    end
  end
end
```

In `lib/metacrunch/marcxml.rb`, add `require_relative "marcxml/writer"` as the last require.

- [ ] **Step 4: Run the tests and the linter**

Run: `bundle exec rake`
Expected: all tests pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add the MARCXML writer sink" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Jobs with Reader and Writer

**Files:**
- Test: `test/integration/jobs_test.rb`

**Interfaces:**
- Consumes: `Reader`, `Writer`, `Marcxml.parse`, `Marcxml.each`, `DataField`; metacrunch's `Metacrunch.job`, `Job#run(argv, workers:, logger:)`, `Metacrunch::Testing.run(job, source:, workers:)`, `Result#status` (`:ok`, `:ok_with_failures`, `:aborted`), `#records`, `#errors` (`[[record, failure]]`, `failure.step`).

- [ ] **Step 1: Write the test**

`test/integration/jobs_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "logger"
require "metacrunch/testing"

class JobsTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_same_output_with_and_without_workers_and_parsing
    outputs = [nil, 2].product([true, false]).map { |workers, parse| run_marking_job(workers:, parse:) }

    assert_equal 1, outputs.uniq.size
    assert_equal ["processed"] * 3, Marcxml.each(outputs.first).map { it.value("999", "a") }
  end

  def test_a_broken_record_fails_alone
    path = File.join(@dir, "broken.xml")
    File.write(path, %(<collection><record><controlfield tag="001">1</controlfield></record>) +
                     %(<record><controlfield tag="001">2</record></collection>))
    job = Metacrunch.job do
      source Marcxml::Reader.new(path)
      on_error :skip
    end
    result = Metacrunch::Testing.run(job)

    assert_equal :ok_with_failures, result.status
    assert_equal 1, result.records.size
    assert_equal "source", result.errors.first.last.step
  end

  def test_testing_run_with_parsed_records
    job = Metacrunch.job do
      map { {"id" => it["001"].value, "title" => it.value("245", "a")} }
    end
    source = Marcxml.each(fixture("collection.xml")).to_a

    [nil, 2].each do |workers|
      result = Metacrunch::Testing.run(job, source:, workers:)

      assert_equal({"id" => "book-1", "title" => "Metadata in practice"}, result.records.first)
    end
  end

  def test_an_aborted_run_leaves_a_well_formed_file
    input = fixture_path("collection.xml")
    output = File.join(@dir, "out.xml")
    job = Metacrunch.job do
      source Marcxml::Reader.new(input)
      map { it["001"].value == "article-1" ? raise("broken") : it }
      sink Marcxml::Writer.new(output)
    end
    result = job.run([], logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_equal ["book-1"], Marcxml.each(File.read(output)).map { it["001"].value }
  end

  private

  def run_marking_job(workers:, parse:)
    input = fixture_path("collection.xml")
    output = File.join(@dir, "out-#{workers}-#{parse}.xml")
    job = Metacrunch.job do
      source Marcxml::Reader.new(input, parse:)
      map(name: "parse") { it.is_a?(String) ? Marcxml.parse(it) : it }
      map(name: "mark") { it.add(Marcxml::DataField.new("999", " ", " ", [["a", "processed"]])) }
      sink Marcxml::Writer.new(output)
    end
    result = job.run([], workers:, logger: Logger.new(nil))

    assert_equal :ok, result.status, result.error
    File.read(output)
  end

end
```

- [ ] **Step 2: Run it**

Run: `bundle exec ruby -Ilib -Itest test/integration/jobs_test.rb`
Expected: PASS (the components exist). If a test fails, the bug is in Reader, Writer or the model: fix it there, test first, not in this test. If `failure.step` is not `"source"`, check metacrunch's `SOURCE_STEP` and use its value.

- [ ] **Step 3: Run the whole suite and the linter**

Run: `bundle exec rake`
Expected: all tests pass, coverage thresholds met, no offenses.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Test jobs with the reader and the writer, also with workers" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Examples, Readme, changelog and benchmark

**Files:**
- Create: `examples/data/catalog.xml` (copy of `test/fixtures/collection.xml`), `examples/marcxml2jsonl.rb`, `examples/cleanup.rb`, `test/integration/examples_test.rb`, `bench/parse.rb`, `CHANGELOG.md`
- Replace: `Readme.md`

**Interfaces:**
- Consumes: everything above; metacrunch's `exe/metacrunch` (`Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")`), `params { param ...; args :files, min: 1 }`, `params.files`.

- [ ] **Step 1: Write the failing examples test**

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

  def test_marcxml2jsonl
    stdout, stderr, status = metacrunch("run", example("marcxml2jsonl.rb"), example("data/catalog.xml"))
    records = stdout.lines.map { JSON.parse(it) }

    assert_predicate status, :success?, stderr
    assert_equal ["book-1", "article-1", "holding-1"], records.map { it["id"] }
    assert_equal "Metadata in practice : a handbook", records.first["title"]
  end

  def test_cleanup_writes_marcxml
    Dir.mktmpdir do |dir|
      output = File.join(dir, "clean.xml")
      _stdout, stderr, status = metacrunch("run", example("cleanup.rb"), "--output", output, example("data/catalog.xml"))
      records = Metacrunch::Marcxml.each(File.read(output)).to_a

      assert_predicate status, :success?, stderr
      assert(records.all? { it.value("883", "a") == "metacrunch cleanup example" })
      assert_empty records.flat_map { it.fields("856", ind2: "2") }
    end
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*args) = Open3.capture3(RbConfig.ruby, BIN, *args)

end
```

Run: `bundle exec ruby -Ilib -Itest test/integration/examples_test.rb`
Expected: FAIL (the example files do not exist).

- [ ] **Step 2: Write the examples**

```bash
mkdir -p examples/data && cp test/fixtures/collection.xml examples/data/catalog.xml
```

`examples/marcxml2jsonl.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch/marcxml"

# Reads MARCXML and writes one JSON object per record (id, title, authors,
# subjects, links) to stdout as JSON Lines.
#
#   bundle exec metacrunch run examples/marcxml2jsonl.rb examples/data/catalog.xml
Metacrunch.job do
  params do
    args :files, min: 1
  end

  source Metacrunch::Marcxml::Reader.new(params.files), id: ->(record) { record["001"]&.value }

  map do |record|
    {
      "id" => record["001"]&.value,
      "title" => record.field("245")&.join("a", "b", separator: " : "),
      "authors" => record.values(["100", "700"], "a"),
      "subjects" => record.values("650", "a"),
      "links" => record.values("856", "u", ind1: "4", ind2: "0")
    }
  end
end
```

`examples/cleanup.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch/marcxml"

# Cleans MARCXML records and writes them as MARCXML again: collapses runs of
# spaces in titles, drops links to cover images (856 with second indicator
# 2) and records the cleanup in field 883.
#
#   bundle exec metacrunch run examples/cleanup.rb --output tmp/clean.xml examples/data/catalog.xml
Metacrunch.job do
  params do
    param :output, String, default: "-", desc: "MARCXML file for the cleaned records (- for stdout)"
    args :files, min: 1
  end

  source Metacrunch::Marcxml::Reader.new(params.files), id: ->(record) { record["001"]&.value }

  map(name: "titles") do |record|
    record.fields("245").each do |field|
      field.subfields.each { it.value = it.value.squeeze(" ").strip }
    end
    record
  end

  map(name: "covers") do |record|
    record.remove("856", ind2: "2")
    record
  end

  map(name: "provenance") do |record|
    record.add(Metacrunch::Marcxml::DataField.new("883", " ", " ", [["a", "metacrunch cleanup example"]]))
  end

  sink Metacrunch::Marcxml::Writer.new(params.output)
end
```

Run: `bundle exec ruby -Ilib -Itest test/integration/examples_test.rb`
Expected: PASS.

- [ ] **Step 3: Write the benchmark and run it**

`bench/parse.rb`:

```ruby
# frozen_string_literal: true

# Measures parsing, splitting, serializing and Marshal on synthetic MARCXML
# with records of about 3 KB.
#
#   bundle exec ruby --yjit bench/parse.rb [RECORDS]
require "metacrunch/marcxml"
require "tmpdir"

Marcxml = Metacrunch::Marcxml
COUNT = Integer(ARGV.fetch(0, "10000"))

def record(number)
  fields = [Marcxml::ControlField.new("001", "record-#{number}"),
            Marcxml::ControlField.new("005", "20240101120000.0"),
            Marcxml::ControlField.new("008", "240101s2024    gw            000 0 eng d")]
  20.times do |index|
    subfields = [["a", "Value #{index} of record #{number} with a few words"], ["b", "Second value"],
                 ["0", "(DE-000)#{number}-#{index}"]]
    fields << Marcxml::DataField.new((100 + (index * 40)).to_s, "1", " ", subfields)
  end
  Marcxml::Record.new(leader: "00000nam a2200000 c 4500", type: "Bibliographic", fields:)
end

def measure(label)
  GC.start
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  micros = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000_000 / COUNT
  puts "#{label.ljust(36)} #{format("%.1f", micros).rjust(8)} µs/record"
end

records = Array.new(COUNT) { record(it) }
Dir.mktmpdir do |dir|
  path = File.join(dir, "records.xml")
  File.open(path, "w") do |file|
    file.write(Marcxml::Writer::HEADER)
    records.each { file.write(it.to_xml(namespace: false)) }
    file.write(Marcxml::Writer::FOOTER)
  end
  yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? " with YJIT" : ""
  puts "#{COUNT} records of #{File.size(path) / COUNT} bytes, Ruby #{RUBY_VERSION}#{yjit}"

  measure("each (from a file)") { File.open(path) { |io| Marcxml.each(io) { nil } } }
  measure("each_xml (from a file)") { File.open(path) { |io| Marcxml.each_xml(io) { nil } } }
  xmls = File.open(path) { Marcxml.each_xml(it).to_a }
  measure("parse (one record string)") { xmls.each { Marcxml.parse(it) } }
  measure("to_xml") { records.each(&:to_xml) }
  measure("Marshal round trip of a record") { records.each { Marshal.load(Marshal.dump(it)) } }
  measure("Marshal round trip of its XML") { xmls.each { Marshal.load(Marshal.dump(it)) } }
end
```

Run: `bundle exec ruby --yjit bench/parse.rb`
Expected: "each (from a file)" at most 30 µs/record. If it is slower, profile before going on (the spike reached about 22 µs). Note the two Marshal numbers for the Readme.

- [ ] **Step 4: Write `CHANGELOG.md`**

```markdown
# Changelog

## 5.0.0 (unreleased)

A rewrite for metacrunch 5. Code written for 4.x must be adapted; see the Readme.

### Breaking changes

- Requires Ruby 4.0 and metacrunch 5. ActiveSupport is no longer a dependency.
- `Metacrunch::Marcxml.parse` returns exactly one record and raises `ParseError` otherwise; `collection_mode:` and
  `Metacrunch.Marcxml(...)` are gone. `Metacrunch::Marcxml.each` streams the records of a collection.
- Records keep fields and subfields in document order as Arrays. `Record::Leader`, `Record::Controlfield`,
  `Record::Datafield`, `Record::Subfield`, `DatafieldSet`, `SubfieldSet` and `Document` are replaced by `Record`,
  `ControlField`, `DataField` and `Subfield`.
- `datafields(...)` and `controlfield(...)` are replaced by `fields(...)`, `field(...)`, `values(...)` and
  `value(...)`. The query strings of `Record#[]` (`"100**a,e"`) are gone; `record[tag]` returns the first field with
  that tag.
- Tags are Strings and are neither truncated nor converted: `fields(245)` raises, four-character tags work.
- The leader is a String. Blank indicators are `" "`; `:blank`, `"#"`, `"-"` and `"_"` are no longer aliases.
- Whitespace, line breaks, CDATA, repeated control fields and the order of subfields are kept as written (4.x
  collapsed whitespace and lost the order). Elements with a namespace prefix are read.
- Values must be valid UTF-8; others raise `ParseError`.

### New

- `Record#to_xml`, `#to_h` (MARC-in-JSON) and `#to_s` (MarcEdit's mnemonic form, also used by `inspect`).
- Changing records: `Record#add`, `#append`, `#remove`, `DataField#add`, `#remove`, deep `dup`.
- `Metacrunch::Marcxml::Reader` (a source for files, gzip files, tar archives, stdin and IOs) and `Writer` (a sink).
- `Metacrunch::Marcxml.each_xml` and `normalize: :nfc`.
```

- [ ] **Step 5: Write `Readme.md`**

Replace the whole file with the text below. In the "Workers" section, put in the two Marshal numbers from Step 3, rounded to whole microseconds.

````markdown
# metacrunch-marcxml

MARCXML for [metacrunch](https://github.com/ubpb/metacrunch): an ordered record model with a plain Ruby API, a fast
parser that keeps the data as written, a serializer, and a source and a sink for metacrunch jobs.

```ruby
require "metacrunch/marcxml"

Metacrunch.job do
  params { args :files, min: 1 }

  source Metacrunch::Marcxml::Reader.new(params.files), id: ->(record) { record["001"]&.value }

  map do |record|
    {
      "id" => record["001"]&.value,
      "title" => record.field("245")&.join("a", "b", separator: " : "),
      "authors" => record.values(["100", "700"], "a"),
      "isbns" => record.values("020", "a")
    }
  end
end
```

```
$ metacrunch run jobs/marcxml2jsonl.rb records.xml.gz > records.jsonl
```

More in [`examples/`](examples): MARCXML to JSON Lines, and a cleanup job that writes MARCXML again.

## Installation

```ruby
# Gemfile
gem "metacrunch-marcxml"
```

Requires Ruby 4.0 and metacrunch 5. The only other dependency is [Ox](https://github.com/ohler55/ox).

## Records

A `Metacrunch::Marcxml::Record` has a `leader` (a String or nil), a `type` (the `type` attribute of `<record>`, e.g.
`"Bibliographic"`, or nil) and `fields`, an Array of `ControlField`s and `DataField`s in document order. A
`DataField` has a `tag`, two indicators (`ind1`, `ind2`; blank is `" "`) and `subfields`, an Array of `Subfield`s
with a `code` and a `value`. Tags and codes are Strings and are not checked, so local tags such as `852H` and codes
such as `as` work.

### Querying

```ruby
record.fields("650")                              # an Array of fields, in record order
record.fields("100", "700")                       # several tags
record.fields("600".."699")                       # a Range of tags
record.fields(/\A6/)                              # a Regexp
record.fields("856", ind1: "4", ind2: ["0", " "]) # indicators: a String or an Array
record.field("245")                               # the first match or nil; record["245"] is the same
record.values("650", "a", ind2: "7")              # the values of $a of the matching fields
record.value("264", "b", ind2: "1")               # the first of those values or nil
record.values("001")                              # control fields give their value
record["008"]&.[](35..37)                         # positions of a control field
record.leader&.[](6)

field = record.field("245")
field.values("a", "b")                            # in field order; without codes all values
field.value("a")                                  # the first; field["a"] is the same
field.join("a", "b", separator: " : ")            # nil if there is no value
field.subfields("a")                              # an Array of Subfields
```

`fields` and `subfields` without arguments return the record's and the field's own Arrays; a query with arguments
returns a new Array. Results are plain Arrays, so they chain with `flat_map`, `filter_map` and friends:
`record.fields("856", ind1: "4").flat_map { it.values("u") }`.

### Changing

```ruby
record.add(Metacrunch::Marcxml::DataField.new("650", " ", "7", [["a", "Linked data"], ["2", "gnd"]]))
record.append(Metacrunch::Marcxml::ControlField.new("009", "x"))
record.remove("856", ind1: "4", ind2: "2")        # returns the removed fields
field.add("a", "Value")                           # appends a subfield
field.remove("x")                                 # returns the removed subfields
field.ind1 = "1"
copy = record.dup                                 # a deep copy
```

`add` inserts a field before the first field whose tag sorts after its tag; `append` adds it at the end. `remove`
without arguments removes all fields (all subfields).

### Output

- `record.to_xml` returns the record as MARCXML; `namespace: false` leaves out `xmlns`.
- `record.to_h` returns MARC-in-JSON: `{"leader" => "...", "fields" => [{"001" => "..."}, {"245" => {"ind1" => "1",
  "ind2" => "0", "subfields" => [{"a" => "..."}]}}]}`.
- `record.to_s` and `inspect` show one line per field as MarcEdit does (`=245  10$aTitle$bSubtitle`), so records are
  readable in `metacrunch trace` and in test failures.

## Parsing

```ruby
Metacrunch::Marcxml.parse(xml)                    # exactly one record from a String
Metacrunch::Marcxml.each(io_or_string) { ... }    # every record, streaming
Metacrunch::Marcxml.each_xml(io_or_string) { ... } # every record as a String, without parsing it
```

`each` and `each_xml` read Strings and IO-like objects (files, `Zlib::GzipReader`, pipes); without a block they
return an Enumerator. Read large inputs from a file or an IO rather than from a String in memory.

The parser keeps what the data says:

- whitespace at the start, at the end and inside values, and line breaks (XML itself turns `\r\n` into `\n`);
- the order of fields and subfields, repeated control fields, empty subfields;
- CDATA, entities, and values interrupted by comments;
- elements with a namespace prefix (`<marc:record>`), the `type` attribute, and a leader anywhere in the record.

A missing or empty indicator becomes `" "`. With `normalize: :nfc` values are normalized to Unicode NFC (some systems
export decomposed characters); by default they are left as they are.

`Metacrunch::Marcxml::ParseError` reports input that is not well-formed (with `line` and `column`), input that ends
inside a record, values that are not valid UTF-8 (MARCXML is UTF-8), and `parse` with no record or several. Several
records without a `<collection>` around them are not well-formed XML for `each`; `each_xml` and the `Reader` read them.
Ox, the XML parser underneath, does not validate and accepts some input that is not well-formed.

`each_xml` cuts the input at the end tags of the records; an end tag inside a CDATA section or a comment cuts a record
there.

## In metacrunch jobs

### Reader

```ruby
source Metacrunch::Marcxml::Reader.new(params.files, normalize: :nfc), id: ->(record) { record["001"]&.value }
```

Reads one target or an Array of them: paths (`.xml`, `.gz`, `.tar`, `.tar.gz`, `.tgz`; every file in an archive is
read as MARCXML), `"-"` for stdin, or IOs, which it does not close. A record that is not well-formed becomes a
`Metacrunch::InvalidRecord` and fails under the job's error policy; the records after it are read. An error of a whole
input (a missing file, a broken gzip file) stops the run. The progress display shows how much of the files has been
read.

### Writer

```ruby
sink Metacrunch::Marcxml::Writer.new(params.output)   # a path (".gz" compresses), "-" for stdout, or an IO
```

Writes one `<collection>` with a `<record>` per record. The closing tag is written also when a run aborts, so the file
stays well-formed. A value with a character that XML 1.0 cannot represent (a control character other than tab and
line breaks) stops the run with the record's position.

### Workers

`--workers` sends records between processes with `Marshal`. A parsed record costs much more to send than its XML: in
`bench/parse.rb`, MARSHAL_RECORD µs per record for a parsed record and MARSHAL_XML µs for its XML string. With
workers, let the reader yield the XML and parse it in the first step:

```ruby
source Metacrunch::Marcxml::Reader.new(params.files, parse: false)
map(name: "parse") { Metacrunch::Marcxml.parse(it) }
```

`id:` then gets the XML string.

### Testing jobs

```ruby
records = Metacrunch::Marcxml.each(<<~XML).to_a
  <collection>
    <record><controlfield tag="001">1</controlfield></record>
  </collection>
XML
result = Metacrunch::Testing.run(job, source: records)
```

## Upgrading from 4.x

See the [changelog](CHANGELOG.md) for all changes. The most common ones:

| 4.x | 5 |
|---|---|
| `Metacrunch::Marcxml.parse(xml, collection_mode: true)` | `Metacrunch::Marcxml.each(xml).to_a` |
| `record.datafields("245", ind2: "0").subfields("a").values` | `record.values("245", "a", ind2: "0")` |
| `record["100**a"]` | `record.values("100", "a")` |
| `record.controlfield("001").value` | `record["001"]&.value` |
| `record.leader.value` | `record.leader` |
| `datafield.subfields("a").first&.value` | `datafield.value("a")` |
| `ind1: :blank` | `ind1: " "` |

## License

MIT; see [License.txt](License.txt).
````

Replace `MARSHAL_RECORD` and `MARSHAL_XML` with the numbers from Step 3.

- [ ] **Step 6: Run the whole suite and the linter**

Run: `bundle exec rake`
Expected: all tests pass, coverage thresholds met, no offenses.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add examples, a benchmark, the changelog and the Readme" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Final check and whole-branch review

**Files:** whatever the review finds.

- [ ] **Step 1: Verify**

Run: `bundle exec rake && bundle exec ruby --yjit bench/parse.rb`
Expected: all tests pass, coverage >= 95 % lines and >= 90 % branches, no offenses; "each (from a file)" at most 30 µs/record.

- [ ] **Step 2: Check the success criteria of the spec (section 1.3)**

Each criterion maps to a test: 1 → `ParseTest` and `ToXmlTest#test_round_trip_of_every_fixture`; 2 → `JobsTest#test_same_output_with_and_without_workers_and_parsing`; 3 → `ReaderTest#test_a_broken_record_is_an_invalid_record` and `JobsTest#test_a_broken_record_fails_alone`; 4 → the benchmark; 5 → `rake`. Search `lib/` for the names of internal systems or institutions (`grep -rniE "alma|paderborn|ubpb" lib examples test`); only the homepage URL in the gemspec and the Readme may contain `ubpb`.

- [ ] **Step 3: Whole-branch review**

Have a fresh reviewer (most capable model) review `git diff master...metacrunch-ng` against the spec and this plan. Fix every finding test first, one commit per topic, and run `bundle exec rake` after each fix.

- [ ] **Step 4: Hand over**

Report the branch, the head commit and the benchmark numbers. Do not push and do not merge.
