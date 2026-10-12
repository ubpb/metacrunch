# metacrunch-marcxml for metacrunch 5

- Date: 2026-10-12
- Branch: `metacrunch-ng` (metacrunch-marcxml)
- Status: approved design; not implemented
- Builds on: metacrunch 5 (`metacrunch-ng` branch of metacrunch), its
  source and sink contracts, `InvalidRecord`, `Metacrunch::Testing`

## 1. Context

metacrunch-marcxml 4.0 parses MARCXML with Ox SAX into a `Record` with
hash-indexed fields and offers a query string (`"100**a,e"`). It has nothing
metacrunch-specific: it is a MARCXML library in the `Metacrunch` namespace,
built on ActiveSupport. metacrunch 5 is a redesign, and its Readme states
that the 4.x extension gems do not work with it yet.

A newer copy of the same code lives in a separate tool (pub). It stays
untouched; this project concerns metacrunch only, and compatibility with
pub or with the 4.x API is not a goal. The analysis of both copies found
data errors in the shared parser and a performance trap in Ox (see 1.5).

### 1.1 Goals

1. Read MARCXML into an ordered, faithful record model: every field,
   subfield, value and whitespace character arrives as it was written.
2. A pure Ruby API to query and modify records, built on Arrays.
3. Write records back as MARCXML, so that MARC to MARC jobs are possible.
4. A metacrunch source (files, stdin, gzip, tar archives) and sink.
5. Fast: parsing at most 30 µs per record of a typical size, and a
   documented fast path for workers.
6. The core (model, parser, serializer) does not reference metacrunch, so
   it can move into a gem of its own later without changes.

### 1.2 Non-goals

- A query string language. MARCspec is the only standard for MARC paths
  and is kept as a later idea (section 11).
- MARC-in-JSON as an input format (`from_h`), binary MARC (ISO 2709),
  MARC-8, validation of tags, indicators or codes against MARC 21.
- Compatibility with the 4.x API (`DatafieldSet`, `SubfieldSet`, query
  strings, `collection_mode:`) or with pub.
- Changes to metacrunch itself.

### 1.3 Success criteria

1. Every case of the table in 1.5 parses correctly, and
   `Marcxml.parse(record.to_xml) == record` holds for every test fixture.
2. A job `Reader -> steps -> Writer` gives byte-identical output with and
   without `workers: 2`, with `parse: true` and with `parse: false`.
3. A record that is not well-formed fails alone as an `InvalidRecord`; the
   records around it are processed.
4. The benchmark (`bench/parse.rb`) shows at most 30 µs per record for
   parsing a file with records of about 3 KB.
5. Tests cover at least 95 % of lines and 90 % of branches; RuboCop is
   clean.

### 1.4 Decisions

| Topic | Decision |
|---|---|
| Gem structure | One gem, `metacrunch-marcxml`. The core does not reference metacrunch; only the components (`Reader`, `Writer`) do. |
| Use cases | Read, query, modify, write MARCXML. `to_h` gives MARC-in-JSON for output and tests; there is no `from_h`. |
| Query API | Ruby methods only, no string syntax. |
| Collections | Plain Arrays of fields and subfields, no set classes. |
| Reader default | `parse: true` yields records; `parse: false` yields XML strings for workers. |
| Test helpers | None; `Marcxml.each(xml).to_a` builds records for `Metacrunch::Testing`. |
| Unicode | Kept as read; `normalize: :nfc` normalizes values on request. |

### 1.5 Findings that shaped the design

The 4.x parser (shared with pub) loses data:

| Input | 4.x result |
|---|---|
| `A  B ` and line breaks in a value | `A B ` (Ox's default `skip: :skip_white` collapses whitespace) |
| `<![CDATA[A & B]]>` | `nil` |
| `A<!-- c -->B` | `B` (each text event replaces the value) |
| `<marc:record>` with a prefix | no record |
| subfields a, b, a | order a, a, b (hash by code) |
| two `007` control fields | only the last one |
| tag `852H` (local tags of some systems) | truncated to `852` |

Measured on a 25 MB export with 8,855 records (Ruby 4.0, YJIT):

| Variant | µs per record |
|---|---|
| 4.x, whole file as a String | 165 |
| 4.x, read from a File | 31.5 |
| prototype: Ox SAX, ordered Arrays, from a File | 21.8 |
| ruby-marc `MARC::XMLReader` (Nokogiri) | 58 |
| splitting into record strings only | 1.2 |
| Marshal round trip of a parsed record / of its XML string | 58 / 1 |
| NFC per non-ASCII value / on the whole XML | 1.9 / 83 |

Ox SAX is superlinear on a `String` or `StringIO` (1.2 s for the file, 86
ms for a quarter of it) but linear on a `File`, a `Zlib::GzipReader`, a
pipe or any object with `readpartial` (56–83 ms).

## 2. Layout and dependencies

```
lib/metacrunch/marcxml.rb              # entry; Marcxml.parse, .each, .each_xml
lib/metacrunch/marcxml/version.rb      # VERSION = "5.0.0.pre"
lib/metacrunch/marcxml/errors.rb       # Error, ParseError, SerializeError
lib/metacrunch/marcxml/subfield.rb
lib/metacrunch/marcxml/control_field.rb
lib/metacrunch/marcxml/data_field.rb
lib/metacrunch/marcxml/record.rb
lib/metacrunch/marcxml/parser.rb       # Ox SAX handler (internal)
lib/metacrunch/marcxml/splitter.rb     # each_xml (internal)
lib/metacrunch/marcxml/serializer.rb   # to_xml (internal)
lib/metacrunch/marcxml/reader.rb       # metacrunch source
lib/metacrunch/marcxml/writer.rb       # metacrunch sink
test/ (Minitest), test/fixtures/*.xml
examples/  bench/parse.rb
```

- `require "metacrunch/marcxml"` loads everything. Only `reader.rb` and
  `writer.rb` require `metacrunch` and use its classes.
- Ruby >= 4.0. Runtime dependencies: `ox` (~> 2.14) and `metacrunch`
  (>= 5.0.0.pre, < 6). No ActiveSupport.
- Development: Minitest, SimpleCov (line 95 %, branch 90 %), rubocop-ubpb
  `ruby.yml`, Rake tasks as in metacrunch. The Gemfile takes metacrunch from
  `ENV.fetch("METACRUNCH_PATH", "../metacrunch")` until 5.0 is released.
- CI: GitHub Actions (Ruby 4.0 and head, Ubuntu and macOS, plus a lint
  job), replacing CircleCI. CI checks out metacrunch's `metacrunch-ng`
  branch next to the gem; it passes once that branch is pushed.
- Removed: the 4.x code and RSpec specs, `.rspec`, `.yardopts`,
  `bin/console`, `.circleci/`.

## 3. Record model

All classes are mutable. `==`, `eql?` and `hash` compare class and
attributes. `dup` and `clone` copy deeply (fields and subfields, not the
frozen state of strings).

### 3.1 Subfield

`Subfield.new(code, value)`; `code` and `value` are Strings with accessors.
`inspect` gives `$aValue` (see 3.6).

### 3.2 ControlField

`ControlField.new(tag, value)`; `tag` and `value` with accessors.
`field[index_or_range]` returns `value[index_or_range]` (e.g.
`field[35..37]`), nil for a nil value.

### 3.3 DataField

`DataField.new(tag, ind1 = " ", ind2 = " ", subfields = [])`. Subfields may
be given as `Subfield`s or as `[code, value]` pairs, which become
`Subfield`s. `tag`, `ind1`, `ind2` have accessors; a blank indicator is
`" "`, and nil given to the constructor or a setter becomes `" "`.

| Method | Result |
|---|---|
| `subfields` | the field's Array of `Subfield`s itself (mutable) |
| `subfields(*codes)` | a new Array of the subfields with these codes, in field order |
| `values(*codes)` | their values; without codes all values |
| `value(*codes)` | the first of those values, or nil |
| `field[code]` | `value(code)` |
| `join(*codes, separator: " ")` | the values joined, or nil if there is none |
| `add(code, value)` | appends a subfield; returns self |
| `remove(*codes)` | removes the subfields with these codes; returns them |

### 3.4 Record

`Record.new(leader: nil, fields: [], type: nil)`. `leader` is a String or
nil, `type` the `type` attribute of `<record>` (e.g. `"Bibliographic"`) or
nil. Both have accessors.

Tag matchers, used by the query methods: a String (equal), an Array of
matchers (any), a Range of Strings (its members, `Range#to_a`) or a Regexp
(`match?`). Indicator filters `ind1:` and `ind2:`: nil (any), a String
(equal) or an Array of Strings (any). With an indicator filter, control
fields never match.

| Method | Result |
|---|---|
| `fields` | the record's Array of fields itself (mutable) |
| `fields(*tags, ind1: nil, ind2: nil)` | a new Array of matching fields, in record order; with only indicator filters, all tags |
| `field(*tags, ind1:, ind2:)` | the first matching field, or nil |
| `record[tag]` | `field(tag)` |
| `values(tags, *codes, ind1:, ind2:)` | values of the matching fields in order: of data fields the values of these codes (all without codes), of control fields their value (only when no codes are given) |
| `value(tags, *codes, ind1:, ind2:)` | the first of those values, or nil |
| `add(field)` | inserts the field before the first field whose tag sorts after it (`String#<=>`), else at the end; returns self |
| `append(field)` | appends the field; returns self |
| `remove(*tags, ind1:, ind2:)` | removes the matching fields; returns them |

`add` and `append` raise `ArgumentError` for objects other than
`ControlField` and `DataField`.

### 3.5 MARC-in-JSON

`record.to_h` returns MARC-in-JSON with String keys:

```ruby
{"leader" => "00000nam a2200000 c 4500",
 "fields" => [{"001" => "123"},
              {"245" => {"ind1" => "1", "ind2" => "0",
                         "subfields" => [{"a" => "Title"}, {"b" => "Sub"}]}}]}
```

`"leader"` is omitted when the leader is nil. `type` is not part of
MARC-in-JSON and is left out.

### 3.6 Text form

`record.to_s` gives one line per field in the mnemonic form of MarcEdit, a
blank indicator written as `\`:

```
=LDR  00000nam a2200000 c 4500
=001  123
=245  10$aTitle$bSub
```

`record.inspect` is `#<Metacrunch::Marcxml::Record` followed by those lines
and `>`. `ControlField#inspect`, `DataField#inspect` give their line,
`Subfield#inspect` `$aTitle`. metacrunch's `trace` shows non-Hash records
with `inspect`, so a record stays readable there.

## 4. Parsing

### 4.1 API

```ruby
Metacrunch::Marcxml.parse(xml, normalize: nil)            # => Record
Metacrunch::Marcxml.each(input, normalize: nil) { |r| }   # streams Records
Metacrunch::Marcxml.each_xml(input) { |xml| }             # record strings
```

- `parse` takes a String that contains exactly one `<record>`, bare or in
  a `<collection>`. It raises `ParseError` for none or more than one, and
  `ArgumentError` for a non-String.
- `each` takes a String or an IO-like object (`readpartial` or `read`) and
  yields every record; without a block it returns an Enumerator. A String
  is wrapped in an internal reader with `readpartial`, never in a
  `StringIO` (see 1.5).
- `normalize:` is nil or `:nfc`; anything else raises `ArgumentError`.

### 4.2 Rules

- Elements are matched by their local name: `marc:record` is `record`.
  `collection`, `record`, `leader`, `controlfield`, `datafield` and
  `subfield` are known; other elements and their content are ignored.
- Text is parsed with `skip: :skip_none` and kept exactly: whitespace at
  the start and end and inside, line breaks. Text and CDATA events are
  appended, so a value split by a comment or CDATA is complete. Entities
  and character references are converted.
- The leader is taken wherever it stands in the record. Fields keep their
  document order; empty elements give `""`.
- A missing or empty `ind1` or `ind2` attribute becomes `" "`; a missing
  `tag` or `code` becomes `""`. The `type` attribute of `<record>` is kept.
- Values are UTF-8 (MARCXML is UTF-8); other encodings are not converted.
- With `normalize: :nfc`, every value that is not ASCII-only is normalized
  with `String#unicode_normalize(:nfc)`.

### 4.3 Errors

`Metacrunch::Marcxml::Error < StandardError`; `ParseError < Error` with
`line` and `column` (nil if unknown) in its message and as readers.

- A syntax error Ox reports through the handler's `error` callback.
- Input that ends inside a record.
- A value that is not valid UTF-8, named by its field (`field 245 $a:
  invalid UTF-8`), and invalid UTF-8 in names or attribute values.
- A value with a character XML 1.0 cannot represent, raw or as a reference
  (`&#31;`), so such a record fails alone instead of in the writer.
- Several records without a `<collection>` around them (not well-formed
  XML); `each_xml` and the `Reader` still read them.
- `parse` with no record or more than one.

Ox is not a validating parser and accepts some malformed input; the
Readme says so.

## 5. Splitting

`each_xml(input)` yields each record as the String from its start tag to
its end tag, without parsing:

- The input is read in chunks (`readpartial` or `read`), so Strings, files,
  gzip readers, tar entries and pipes are handled the same way.
- The record element name is detected from the first `<record` or
  `<prefix:record` start tag (followed by whitespace, `>` or `/`), and the
  input is cut after each matching end tag.
- Text before the first record (XML declaration, `<collection>`) and after
  the last one is skipped. A record keeps its bytes; namespace declarations
  of the collection are not copied into it, which the parser does not need.
- A record cut off by the end of the input (an interrupted download) is
  yielded as it is, from its start tag on, so parsing it raises
  `ParseError` and the `Reader` yields an `InvalidRecord`.
- Limit, documented: an end tag inside CDATA or a comment cuts a record.

## 6. Serializing

`record.to_xml(namespace: true)` returns the record as MARCXML, one element
per line, indented by 2 spaces:

```xml
<record xmlns="http://www.loc.gov/MARC21/slim" type="Bibliographic">
  <leader>00000nam a2200000 c 4500</leader>
  <controlfield tag="001">123</controlfield>
  <datafield tag="245" ind1="1" ind2="0">
    <subfield code="a">Title</subfield>
  </datafield>
</record>
```

- `namespace: false` omits `xmlns` (the writer declares it on
  `<collection>`). `type` is written when set; the leader is written first
  when set; the fields follow in record order.
- Text escapes `&`, `<`, `>`; attributes also `"`. A carriage return is
  written as `&#13;`, a tab and a line feed in attributes as `&#9;` and
  `&#10;`, so they survive parsing.
- Characters XML 1.0 cannot represent (U+0000–U+0008, U+000B, U+000C,
  U+000E–U+001F, U+FFFE, U+FFFF) and invalid UTF-8 raise `SerializeError`
  naming the tag (and code).

## 7. Source: `Metacrunch::Marcxml::Reader`

```ruby
source Metacrunch::Marcxml::Reader.new(params.files, normalize: :nfc),
       id: ->(record) { record["001"]&.value }
```

`Reader.new(targets, parse: true, normalize: nil)`:

- `targets`: a path (String or Pathname), `"-"` for stdin, an IO, or an
  Array of those; an empty Array raises `ArgumentError`. IOs are never
  closed; files are closed when `each` ends, also by `break` or an error.
- Kind by name: `.tar.gz` and `.tgz` (tar in gzip), `.tar`, `.gz`, else
  plain XML. Every regular file in a tar archive is read as MARCXML, in
  archive order.
- `each` splits each input with `each_xml`. With `parse: true` it parses
  each record string and yields the `Record`; a `ParseError` yields
  `Metacrunch::InvalidRecord.new(raw: xml, error: e)` instead, which fails
  under the job's error policy. With `parse: false` it yields the strings.
- Errors of an input as a whole (missing file, broken gzip) raise and stop
  the run, as for every source.
- `progress`: bytes read of all files (compressed position for gzip and
  tar.gz) divided by their total size; nil when a target is stdin, an IO or
  not a regular file.

## 8. Sink: `Metacrunch::Marcxml::Writer`

```ruby
sink Metacrunch::Marcxml::Writer.new(params.output)
```

`Writer.new(target)`: a path, `"-"` for stdout or an IO; a path ending in
`.gz` is compressed.

- `open` writes `<?xml version="1.0" encoding="UTF-8"?>` and
  `<collection xmlns="http://www.loc.gov/MARC21/slim">`.
- `write(record, ctx)` and `write_batch(records, ctxs)` write each record
  as `to_xml(namespace: false)` would, with every element indented by two
  more spaces; the indentation never goes into a value (a value with a line
  break stays unchanged).
- `close` writes `</collection>`, also after an aborted run, and closes its
  own file (an IO from outside is only flushed). A run without records
  gives an empty collection.
- A record that is not a `Metacrunch::Marcxml::Record`, or one that raises
  `SerializeError`, raises `Metacrunch::Error` with its position, as the
  JSON Lines writer does.
- `Errno::EPIPE` raises `SignalException("PIPE")` once; afterwards the
  writer writes nothing, not even the closing tag.

## 9. Tests

Minitest, one test file per class, written test first. Fixtures in
`test/fixtures/` are hand-written, generic records (a book, an article, a
holdings record with four-character local tags and multi-character
subfield codes).

- **Model:** tag matchers (String, Array, Range, Regexp), indicator
  filters (String, Array, nil, control fields), `value`, `values`, `[]`,
  `join`, `subfields`; `add` (sorted, also with `852H` and control
  fields), `append`, `remove` and their return values; deep `dup`; `==`;
  `to_h`; `to_s` and `inspect`.
- **Parser:** every case of 1.5; entities and character references;
  default namespace; leader after control fields; empty subfields; missing
  indicators; `type`; inputs String, File, StringIO, `Zlib::GzipReader`,
  pipe; `normalize: :nfc` (decomposed input); syntax errors with line and
  column; input that ends inside a record; `parse` with 0 and 2 records;
  the Enumerator of `each`.
- **Splitter:** collection and bare record, prefixed elements, head and
  tail, whitespace and comments between records, empty input, a record that
  spans chunk boundaries.
- **Serializer:** escaping in text and attributes, `\r`, tab and line feed
  in attributes, every forbidden character class and invalid UTF-8,
  `namespace:`, `type`, leader first, no leader; the round trip
  `parse(to_xml) == record` for every fixture.
- **Reader:** path, Pathname, `"-"`, IO (left open), several targets,
  `.gz`, `.tar`, `.tar.gz`, `.tgz` (archives built in the test with
  `Gem::Package::TarWriter`); `parse: false`; `InvalidRecord` with the
  following records still read; `normalize:`; `progress`; files closed on
  `break` and on errors.
- **Writer:** path, `"-"`, IO, `.gz`; header and closing tag; empty run;
  `write_batch`; closing tag after an aborted run; the errors with
  position; EPIPE.
- **Integration:** a job `Reader -> map -> Writer` through `job.run` and
  `Metacrunch::Testing.run`, with and without `workers: 2`, with
  `parse: true` and `parse: false`: byte-identical output.

`bench/parse.rb` generates synthetic MARCXML and measures parsing,
splitting, serializing and Marshal; it does not run in CI.

## 10. Documentation

- Readme (English, generic examples): installation, a first job, the
  record API, parsing (`parse`, `each`, `each_xml`, `normalize:`), `Reader`
  and `Writer`, workers (`parse: false` and the Marshal numbers from the
  benchmark), what the parser keeps and its limits, errors, upgrading from
  4.x.
- `CHANGELOG.md`: "5.0.0 (unreleased)" with the breaking changes: ordered
  Arrays instead of `DatafieldSet`/`SubfieldSet`, no query strings, no
  `collection_mode:`, new class names, no ActiveSupport, Ruby 4.0,
  whitespace and order kept.
- `examples/marcxml2jsonl.rb` (MARCXML to JSON Lines) and
  `examples/cleanup.rb` (MARC to MARC, writes MARCXML), with generic data.

## 11. Deferred

- A MARCspec query language (`245$a$b`, `008/35-37`, subspecs). MARCspec
  tags have exactly three characters; four-character local tags need an
  extension.
- `from_h` and a MARC-in-JSON source.
- Multi-member gzip files (`cat a.gz b.gz`).
- Moving the core into a gem of its own.
