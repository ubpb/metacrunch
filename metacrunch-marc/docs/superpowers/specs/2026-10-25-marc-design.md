# metacrunch-marc: MARCXML, ISO 2709 and MARC-in-JSON on one record model

Date: 2026-10-25. Branch `metacrunch-ng-marc` (from `metacrunch-ng` 49771b3)
of the repository that is now `ubpb/metacrunch-marcxml` and becomes
`ubpb/metacrunch-marc`.

## 1. Context

metacrunch-marcxml on branch `metacrunch-ng` (spec
`2026-10-12-marcxml-ng-design.md`, extended by the IO layer of metacrunch
sub-project 11) reads, queries, changes and writes MARCXML. Its record model
(`Record`, `ControlField`, `DataField`, `Subfield`) and its query API know
nothing about XML; only the parser, the splitter and the serializer do.

Most MARC data outside XML is exchanged as ISO 2709 ("binary MARC", `.mrc`),
and MARC-in-JSON is the common JSON form. This project turns the gem into
`metacrunch-marc`: one record model and one query API, three formats, a source
that detects the format of each document and a sink that writes the format it
is told. metacrunch-marcxml 5 was never released, so the rename costs no
compatibility.

### 1.1 Goals

1. Read and write ISO 2709 (UTF-8) and MARC-in-JSON (one record per line)
   with the record model and query API of metacrunch-marcxml, unchanged.
2. Keep every feature of metacrunch-marcxml (parser rules, speed, workers,
   `normalize: :nfc`, IO layer).
3. A source that reads all three formats, detected by content per document, so
   a job never names its input format and mixed inputs work.
4. A sink with an explicit `format:`.
5. Any record read from any format can be written as MARCXML and
   MARC-in-JSON; what a serializer writes, the parsers read.
6. Tolerant ISO 2709 reading where no data is lost (wrong lengths, base
   address, leader/09 label, padding); strict where guessing would change
   data.
7. Fast: ISO 2709 parsing at most 15 µs and writing at most 10 µs per record of
   about 3 KB; MARCXML unchanged.
8. The core (model, parsers, serializers) still does not reference metacrunch.

### 1.2 Non-goals

- MARC-8 (decoding or encoding). Such records fail with a hint to convert them
  first.
- MarcEdit's mnemonic format (`.mrk`), ALEPHSEQ, MarcXchange, Turbomarc, the
  yaz line format, MicroLIF, the LoC MARC-JSON draft.
- JSON arrays of records.
- Validation against MARC 21 (tag meanings, indicator values, required
  fields).
- A `format:` override on the Reader.
- Changes to metacrunch itself.

### 1.3 Success criteria

1. All tests are green, among them the moved tests of metacrunch-marcxml, the
   round trips of 11.4 and the interop tests against ruby-marc (11.5).
2. Jobs `Reader -> steps -> Writer` give byte-identical output with and
   without `workers: 2`, with `parse: true` and `parse: false`, for every
   output format. Serializing in a step (10) gives the same bytes for ISO 2709
   and MARC-in-JSON and the same records for MARCXML, whose record Strings
   are not indented as the Writer indents them.
3. `bench/parse.rb` (records of about 3 KB as MARCXML, Ruby 4.0 with YJIT)
   shows at most 15 µs per record for `Marc::Iso2709.parse` of one record
   String, at most 10 µs for `to_iso2709`, and at most 30 µs for
   `Marc::Xml.each` from a file, as for metacrunch-marcxml.
4. Tests cover at least 95 % of lines and 90 % of branches; RuboCop
   (rubocop-ubpb `ruby.yml`) is clean.

### 1.4 Decisions

| Topic | Decision |
|---|---|
| Formats | MARCXML, ISO 2709 (UTF-8), MARC-in-JSON (one record per line). No MARC-8, no `.mrk`. |
| Repository | `ubpb/metacrunch-marcxml` is renamed to `ubpb/metacrunch-marc` on GitHub (by the user); history, issues and CI stay. |
| Gem | `metacrunch-marc`, version `1.0.0.pre`, namespace `Metacrunch::Marc`. |
| API shape | One `Reader` that detects the format by content; one `Writer` with a required `format:`; format modules `Marc::Xml`, `Marc::Iso2709`, `Marc::Json` with the same functions for library use. |
| Format symbols | `:xml`, `:iso2709`, `:json`. |
| Values | One rule for all parsers and serializers (3.1). |
| ISO framing | By the record terminator `0x1D`; leader length, base address and directory lengths are not used. |
| Control or data field | By content: a field with a subfield delimiter is a data field. |
| Leader/09 | Not trusted: data is read as UTF-8; invalid UTF-8 with a blank leader/09 gets a MARC-8 hint. |
| Oversize records | `oversize: :error` by default; `:allow` writes numbers that do not fit as all nines. |
| JSON framing | One record per line; arrays are refused with a hint. |
| Interop tests | ruby-marc 1.4 as a development dependency (Gemfile only). |

### 1.5 Findings that shaped the design

**Terms.** MARC 21 is the MARC format in use today (successor of USMARC and
CAN/MARC); it defines a record structure and content designation (tags,
indicators, subfield codes). Its structure is an implementation of ISO 2709
(ANSI Z39.2), its native transmission syntax; a "MARC file" (`.mrc`, `.dat`)
is MARC 21 in ISO 2709. MARCXML (`http://www.loc.gov/MARC21/slim`) carries the
same records in XML. UNIMARC uses the same ISO 2709 structure with other tags.
Sources: https://www.loc.gov/marc/faq.html,
https://www.loc.gov/marc/specifications/specrecstruc.html,
https://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd.

**ISO 2709 in MARC 21** (https://www.loc.gov/marc/specifications/specrecstruc.html,
https://www.loc.gov/marc/bibliographic/bdleader.html):

- Leader: 24 ASCII characters. 00–04 record length (with the terminator),
  09 character coding scheme (blank MARC-8, `a` UCS/Unicode, UTF-8 only),
  10 indicator count (2), 11 subfield code count (2), 12–16 base address of
  data, 20–23 entry map `4500`.
- Directory from byte 24, ended by a field terminator: 12-byte entries of tag
  (3), field length (4), start relative to the base address (5).
- Field terminator `0x1E`, record terminator `0x1D`, subfield delimiter
  `0x1F`. All lengths count octets, also in UTF-8.
- Limits: 99,999 bytes per record, 9,999 per field.
- Control fields `00X` have no indicators and subfields; data fields have two
  indicators and at least one subfield. Real data has alphabetic tags too
  (Aleph `FMT`, Alma enrichment tags such as `AVA`).

**Real data.** DNB delivers ISO 2709 and MARCXML in UTF-8, decomposed (NFD).
Alma publishes binary MARC or MARCXML. LC MDS and OCLC deliveries still
default to MARC-8. Common defects: wrong record lengths, directory lengths
counted in characters after a MARC-8 to UTF-8 conversion, blank leader/09 on
UTF-8 data, line breaks or padding between records, records over 99,999 bytes
(bibliographic records with many embedded items).

**Tools.**

| Tool | Formats | Format choice | Tolerant ISO reading | MARC-8 | Oversize write | Control field rule |
|---|---|---|---|---|---|---|
| ruby-marc 1.4 | ISO, XML, MiJ lines | class | `ForgivingReader` (splits on terminators, swallows errors) | read | raise; `allow_oversized` writes zeros | tags 000–009, extendable |
| pymarc 5.4 | ISO, XML, MiJ, .mrk | class | yields `None`, keeps the exception | read | no check (corrupt) | numeric < 010 |
| MARC4J | ISO, XML, 2 JSONs, .mrk | sniffs first bytes | permissive reader repairs, errors on the record | read, write | throw; `allowOversizeEntry` writes nines | `00` + digit |
| Catmandu::MARC | ISO, XML, MiJ, .mrk, Line, ALEPHSEQ | `type` | RAW importer splits on terminators, `skip_errors` | no | clamps to 99999 | numeric < 10; RAW: no `0x1F` = control |
| Metafacture | ISO (UTF-8 only), XML | command | reads to `0x1E` | no | throws | prefix `00` |
| yaz-marcdump | ISO, XML, MarcXchange, Turbomarc, line, JSON | `-i`/`-o` | resyncs on `0x1D`, directory to `0x1E` | yes | drops fields | `00X` unless `0x1F` follows |

ruby-marc's writer rewrites `record.leader` in place; yaz refuses record
lengths below 25, so ruby-marc's `00000` breaks it, while all nines are read
by MARC4J's permissive reader, Perl MARC and yaz.

**Spike** (throwaway, records of 3 KB as MARCXML, 1.2 KB as ISO 2709, Ruby
4.0 with YJIT, arm64 Mac): `Marcxml.parse` of one record string 37.1 µs,
pure-Ruby ISO 2709 parse 11.2 µs, `to_xml` 19.5 µs, ISO 2709 write 7.2 µs,
splitting a stream at `0x1D` 0.1 µs, Marshal round trip of an ISO string
0.6 µs. ISO 2709 needs no dependency.

**A Readme error.** The metacrunch-marcxml Readme says that a record cut off
by the end of a file stops the run with `Metacrunch::InputError`; the reader
yields it as an `InvalidRecord` (test
`test_a_truncated_file_ends_with_an_invalid_record`). The new Readme states
what the code does.

## 2. Layout, names, migration

```
lib/metacrunch/marc.rb                 # entry; Marc.parse, Marc.check_normalize
lib/metacrunch/marc/version.rb         # VERSION = "1.0.0.pre"
lib/metacrunch/marc/errors.rb          # Error, ParseError, SerializeError
lib/metacrunch/marc/values.rb          # the common rule of 3.1 (internal)
lib/metacrunch/marc/formats.rb         # detection (internal)
lib/metacrunch/marc/delimited.rb       # cuts input after a byte: ISO 2709 records, JSON lines (internal)
lib/metacrunch/marc/subfield.rb
lib/metacrunch/marc/control_field.rb
lib/metacrunch/marc/data_field.rb
lib/metacrunch/marc/record.rb          # + Record.from_h, #to_iso2709
lib/metacrunch/marc/filter.rb, codes.rb, tags.rb
lib/metacrunch/marc/xml.rb             # Marc::Xml.parse, .each, .each_raw
lib/metacrunch/marc/xml/parser.rb, splitter.rb, serializer.rb, string_source.rb, io_source.rb
lib/metacrunch/marc/iso2709.rb         # Marc::Iso2709.parse, .each, .each_raw
lib/metacrunch/marc/iso2709/parser.rb, serializer.rb
lib/metacrunch/marc/json.rb            # Marc::Json.parse, .each, .each_raw
lib/metacrunch/marc/json/parser.rb, serializer.rb
lib/metacrunch/marc/reader.rb          # metacrunch source
lib/metacrunch/marc/writer.rb          # metacrunch sink
test/ (Minitest), test/fixtures/*.xml, *.mrc, *.jsonl
examples/  bench/parse.rb
```

- `require "metacrunch/marc"` loads everything; only `reader.rb` and
  `writer.rb` require `metacrunch`.
- Ruby >= 4.0. Runtime dependencies: `ox` (~> 2.14, MARCXML only),
  `metacrunch` (>= 5.0.0.pre, < 6); `json` is part of Ruby. ISO 2709 needs
  nothing.
- Development: as before (Minitest, SimpleCov, rubocop-ubpb, Rake), plus
  `marc` (~> 1.4) in the Gemfile's development group for the interop tests.
- gemspec: name `metacrunch-marc`, summary "MARC for metacrunch: MARCXML, ISO
  2709 and MARC-in-JSON on one ordered record model, with a source and a
  sink", homepage `https://github.com/ubpb/metacrunch-marc`.
- CI (GitHub Actions) stays as it is.

Every format module offers the same three functions:

| Function | Returns |
|---|---|
| `parse(string, normalize: nil)` | exactly one record; `ParseError` for none or several |
| `each(input, normalize: nil)` | every record, streaming; an Enumerator without a block |
| `each_raw(input)` | every record as a String in its format, without parsing it; an Enumerator without a block |

`input` is a String or an object with `readpartial` or `read`, as for
`Marcxml.each` today.

Renames from metacrunch-marcxml:

| metacrunch-marcxml (ng) | metacrunch-marc |
|---|---|
| `Metacrunch::Marcxml::Record`, `ControlField`, `DataField`, `Subfield`, `Error`, `ParseError`, `SerializeError` | `Metacrunch::Marc::...` |
| `Marcxml.parse(xml)` | `Marc::Xml.parse(xml)`, or `Marc.parse(string)` (7) |
| `Marcxml.each(io)` | `Marc::Xml.each(io)` |
| `Marcxml.each_xml(io)` | `Marc::Xml.each_raw(io)` |
| `Marcxml.check_normalize` | `Marc.check_normalize` |
| `Marcxml::NAMESPACE` | `Marc::Xml::NAMESPACE` |
| `Marcxml::Writer::HEADER`, `FOOTER` | `Marc::Xml::HEADER`, `FOOTER` |
| `Marcxml::Reader.new(files, ...)` | `Marc::Reader.new(files, ...)` |
| `Marcxml::Writer.new(target)` | `Marc::Writer.new(target, format: :xml)` |

The changelog starts at 1.0.0 and names the gem the successor of
metacrunch-marcxml; its "Upgrading from 4.x" table maps metacrunch-marcxml 4.x
to metacrunch-marc.

## 3. Record model and what each format can hold

The model is unchanged: `Record` (leader, `type`, a frozen Array of fields with
a tag index), `ControlField`, `DataField`, `Subfield`, with the query and
change API of metacrunch-marcxml. Tags, indicators and codes are Strings that
the model does not check. Each parser and serializer checks what its format
can hold.

### 3.1 The common rule

Every parser and every serializer requires of the leader, tags, indicators,
codes and values:

- valid UTF-8 (serializers transcode Strings in other encodings and take
  binary Strings as UTF-8, as the MARCXML serializer does now);
- no character that XML 1.0 cannot represent: control characters other than
  tab, line feed and carriage return, and U+FFFE, U+FFFF.

Parsers raise `ParseError`, serializers `SerializeError`, naming the place.
So any record read from any format can be written as MARCXML and
MARC-in-JSON, and the ISO 2709 separators (`0x1D`–`0x1F`) never reach a value.
The rule moves from `Serializer.unrepresentable` into `Marc::Values`
(internal), used by all parsers and serializers.

`normalize: :nfc` normalizes values (leader, control field and subfield
values) for every format, as it does for MARCXML now.

### 3.2 Limits per format

| | MARCXML | ISO 2709 | MARC-in-JSON |
|---|---|---|---|
| tag | any | exactly 3 ASCII characters | any |
| indicator | any | exactly 1 ASCII character | any |
| code | any | exactly 1 ASCII character | any |
| data field without subfields | written | refused (it would be read back as a control field) | written |
| leader | written if present | 24 ASCII characters, or generated (3.3) | written if present |
| `type` | written | dropped | dropped |
| size | no limit | 9,999 bytes per field, 99,999 per record (5.5) | no limit |

A serializer raises `SerializeError` for a record beyond its limits, e.g.
`field 852H: an ISO 2709 tag has 3 ASCII characters`.

### 3.3 Leader

Parsers keep the leader exactly as read, including stale lengths. The ISO 2709
serializer writes these positions into its output and never changes
`record.leader`:

| Positions | Written |
|---|---|
| 00–04 | record length |
| 09 | `a` (the output is UTF-8) |
| 10–11 | `22` |
| 12–16 | base address of data |
| 20–22 | `450` |

All other positions, 23 included (UNIMARC has a blank there), are copied. A
record without a leader is written with `00000    a2200000   4500` and the
computed positions filled in.

### 3.4 `Record.from_h(hash)`

Builds a record from MARC-in-JSON as `Record#to_h` returns it:

```ruby
{"leader" => "00000nam a2200000 c 4500",
 "fields" => [{"001" => "123"},
              {"245" => {"ind1" => "1", "ind2" => "0", "subfields" => [{"a" => "Title"}]}}]}
```

- Keys are Strings. The top level has `"fields"` (an Array) and optionally
  `"leader"` (a String or nil); other keys raise.
- Each field is a Hash with exactly one key, its tag. A String value makes a
  `ControlField`; a Hash makes a `DataField`, with the keys `"ind1"`,
  `"ind2"` (Strings; missing or nil becomes `" "`) and `"subfields"` (required;
  an Array, possibly empty, of Hashes with exactly one key, the code, and a
  String value); other keys raise.
- Values that are not Strings raise, e.g. `{"001" => 123}`.
- The common rule applies; `normalize:` is accepted as by the parsers.
  Strings in other encodings are transcoded and binary Strings taken as
  UTF-8, as the serializers do.
- Errors raise `ParseError` with a path: `fields[3] (245) subfields[0]: a
  value must be a String, got 12`.

`Record.from_h(record.to_h) == record` holds for every record without a
`type` whose values are Strings that keep to the common rule, so for every
record a parser read.

### 3.5 Errors

`Metacrunch::Marc::Error` is the base class; `ParseError` keeps `line` and
`column` (set for MARCXML from Ox, nil for the other formats, whose messages
say where instead, e.g. `directory entry 4 (245): ...`); `SerializeError` is
raised by serializers.

## 4. MARCXML

Moves unchanged into `Marc::Xml`: the Ox SAX parser and its rules, the splitter
(`each_xml` becomes `each_raw`), the serializer, `StringSource` and
`IoSource`, and `Record#to_xml(namespace: true)`. Only the common rule moves to
`Marc::Values`, and `HEADER`/`FOOTER` move from the Writer to `Marc::Xml`.
The limits of metacrunch-marcxml stay (elements matched by local name, end tags
inside CDATA cut a record).

## 5. ISO 2709

### 5.1 API

```ruby
Metacrunch::Marc::Iso2709.parse(string)            # one record
Metacrunch::Marc::Iso2709.each(io) { |record| }    # streaming
Metacrunch::Marc::Iso2709.each_raw(io) { |raw| }   # record strings, unparsed
record.to_iso2709                                  # a String (UTF-8)
record.to_iso2709(oversize: :allow)
```

Constants: `Marc::Iso2709::RECORD_TERMINATOR = "\x1D"`, `FIELD_TERMINATOR =
"\x1E"`, `SUBFIELD_DELIMITER = "\x1F"`.

### 5.2 Framing (`each_raw`, `Marc::Delimited`)

- A record runs from its first byte up to and including the next `0x1D`. The
  record length in the leader is not used, so wrong lengths and records over
  99,999 bytes with `99999` or `00000` in the leader are read.
- Space, tab, carriage return, line feed and NUL between records are skipped
  (line breaks after each record, padded blocks), and so is a UTF-8 byte order
  mark at the start of the input, which detection skips too (7).
- Bytes left at the end without a `0x1D` are a record cut off by the end of
  the input; they are yielded as they are and fail when parsed (`ParseError`:
  the input ended inside a record), as in MARCXML.
- The input is read in chunks of 64 KiB, searches go on where they stopped,
  and taken records are dropped once they exceed a chunk, so time grows in
  proportion to the input. There is no limit on the size of a record.
- Raw records are Strings in UTF-8 encoding (possibly invalid) including the
  terminator.

### 5.3 Parsing one record (`Iso2709::Parser`)

`parse(string)` skips the bytes of 5.2 at both ends, then requires exactly one
record ending in `0x1D` (several raise `ParseError` with their number, as
`Marc::Xml.parse` does; none or a missing terminator raise).

| Part | Rule |
|---|---|
| Leader | The first 24 bytes; fewer, or characters other than ASCII, raise. Kept as read. |
| Leader 00–04, 10–11, 12–16 | Not used. Two indicators and one-character codes are assumed, as in ruby-marc and pymarc. |
| Directory | From byte 24 to the first `0x1E` (as yaz reads it); none raises. Its length must be a multiple of 12. |
| Directory entries | Tag: 3 ASCII characters, else `ParseError`. Length: not used. Start: 5 digits, not less than the start before it, else `ParseError`. |
| Data | The bytes after the directory up to the `0x1D`, split on `0x1E`; a last `0x1E` before the `0x1D` may be missing. The number of pieces must equal the number of entries, else `ParseError`; the nth piece belongs to the nth entry. |
| Control or data field | A piece containing `0x1F` is a data field, any other a control field (also an empty piece). |
| Data field | Exactly 2 characters before the first `0x1F` are the indicators, else `ParseError`. Each part after a `0x1F`: its first character is the code, the rest the value (possibly empty); an empty part (`0x1F0x1F`, or `0x1F` at the end) raises. |
| Encoding | Bytes are read as UTF-8, whatever leader/09 says; then the common rule. |

Why these rules:

- Lengths and base address are not used, because wrong ones are the most
  common defect and the terminators say the same thing. Start offsets that
  do not decrease are kept as a check: lengths counted in characters still
  pass, while data stored in another order than the directory (allowed by ISO
  2709, not seen in practice) fails instead of pairing tags with the wrong
  data.
- Control or data by content: a control field cannot contain `0x1F` (3.1), so
  no valid field is misread; local control fields such as `FMT` stay control
  fields, `00X` data fields of other MARC dialects stay data fields. Most tools
  decide by tag (1.5). A data field without subfields reads as a control field
  with its indicators as value; the serializer refuses to write one (5.4).
- Indicators and codes are read as characters, so nothing is lost; the
  serializer requires ASCII (3.2).

Invalid UTF-8 raises `ParseError` naming the field, and so does an ESC, with
which MARC-8 switches to Cyrillic, Greek, Hebrew, Arabic or CJK (common in 880
fields; the bytes are ASCII). When leader/09 is blank, the message of both
adds (ESC amended after the review):

```
leader/09 says MARC-8; convert the file to UTF-8 first, e.g. yaz-marcdump -f MARC-8 -t UTF-8 -o marc -l 9=97 in.mrc > out.mrc
```

MARC-8 data that is plain ASCII is identical in UTF-8 and is read.

### 5.4 Serializing (`Iso2709::Serializer`, `Record#to_iso2709`)

- Output: leader, directory, `0x1E`, the fields, `0x1D`. Fields keep record
  order in directory and data; nothing is sorted.
- A control field is its value and `0x1E`; a data field is `ind1`, `ind2`,
  then `0x1F`, code and value per subfield, then `0x1E`.
- Lengths and starts count UTF-8 bytes; the leader is written as in 3.3.
- The result is a String in UTF-8 encoding.
- `SerializeError`, naming the field: a tag that is not 3 ASCII characters,
  an indicator or code that is not 1 ASCII character, a data field without
  subfields, a leader that is not 24 ASCII characters (it is not padded), the
  common rule, and oversize data with `oversize: :error` (5.5).

### 5.5 Oversize records

A field over 9,999 bytes (indicators, codes and terminator included) or a
record over 99,999 bytes:

- `oversize: :error` (the default) raises `SerializeError`: `the record has
  123456 bytes, ISO 2709 allows 99999 (oversize: :allow writes it anyway)`,
  `field 852 has 10234 bytes, ISO 2709 allows 9999 ...`.
- `oversize: :allow` writes every number that does not fit its positions as
  all nines: record length `99999`, field length `9999`, start or base address
  `99999`. MARC4J's permissive reader, Perl MARC and yaz read such records up
  to the `0x1D`, and so does this gem (5.2, 5.3: equal starts pass). Strict
  readers that frame by the record length do not; hence the default.

Other values raise `ArgumentError`.

### 5.6 Not supported

Documented in the Readme: MARC-8 beyond ASCII (5.3), continued fields (a
field over 9,999 bytes split into several directory entries; the piece count
check fails), indicator counts other than 2 and code lengths other than 1.

## 6. MARC-in-JSON

### 6.1 API

```ruby
Metacrunch::Marc::Json.parse(string)          # one record: one JSON object, also over several lines
Metacrunch::Marc::Json.each(io) { |record| }  # every line, streaming
Metacrunch::Marc::Json.each_raw(io) { |line| }
Metacrunch::Marc::Record.from_h(hash)         # from a Hash already parsed
record.to_h                                   # unchanged
record.to_json                                # one line, without its line break
```

### 6.2 Framing

One record per line (JSON Lines), as ruby-marc's `JSONLReader` and Catmandu
read MARC-in-JSON. Blank lines and a byte order mark at the start of a line
are skipped, as in `Metacrunch::JsonLines::Reader`. `each_raw` yields the
lines without their line break (`\n` or `\r\n`). A line that fails to parse
and is not a whole object (it does not start with `{` and end with `}`), as
in a pretty-printed file, gets the hint `MARC-in-JSON has one record per
line; jq -c . in.json > out.jsonl converts pretty-printed JSON`. JSON arrays are not read: the Reader refuses a
document that starts with `[` (7), and `Json.parse` of an array raises
`ParseError` (`a record must be a JSON object`).

### 6.3 Parsing

The line must be valid UTF-8, then `JSON.parse` (duplicate keys raise, as in
`Metacrunch::JsonLines::Reader`), then `Record.from_h` (3.4). Every problem
raises `ParseError`; a `JSON::ParserError` is wrapped with its message.

### 6.4 Serializing

`record.to_json` is `JSON.generate(record.to_h)` after the common rule (3.1),
so a character that XML cannot represent raises `SerializeError` although JSON
could escape it; values that are not Strings are written as their `to_s` and
nil as `""`, as the other serializers do. `type` is dropped. The Writer adds
`"\n"`. (Amended after the review: `JSON.generate(record.to_h)` in a worker
step skipped the rule and could write lines the parser refuses.)

## 7. Detection and `Marc.parse`

`Marc::Formats` (internal) looks at the first bytes of a document after a UTF-8
byte order mark and after space, tab, carriage return, line feed and NUL:

| Start | Format |
|---|---|
| `<` | `:xml` |
| `{` | `:json` |
| 5 digits at 0–4 and 5 digits at 12–16 (record length, base address) | `:iso2709` |
| `[` | error: a JSON array (6.2) |
| nothing (empty, or only skipped bytes) | no records |
| anything else | error: not MARC |

The base address check makes a CSV file that starts with a number fail
clearly instead of being framed as one large invalid record.

`Metacrunch::Marc.parse(string, normalize: nil)` detects the format of a
String by the same rule and parses exactly one record with that format's
`parse`. A String the rule cannot tell that starts with a digit and ends with
the record terminator is taken as ISO 2709: one record needs no record length
or base address, as `Iso2709.parse` does not use them. (Amended after the
review: otherwise `parse: false` with `Marc.parse` refused records that
`parse: true` read.) It raises `ParseError` for a JSON array, for a String without a
record and for one it cannot detect: `neither MARCXML, ISO 2709 nor
MARC-in-JSON: it starts with "id;title;..."`. It is the parse step for raw
records in workers (10).

## 8. Source: `Metacrunch::Marc::Reader`

```ruby
Metacrunch::Marc::Reader.new(targets, parse: true, normalize: nil)
```

- `targets`: what `Metacrunch::Input` takes (paths, `"-"`, IOs, Arrays of
  them; gzip and tar unpacked by content). IOs are not closed.
- `each_document` gives the streams; each document is detected on its own
  (7), so a tar archive may mix formats. The stream is peeked in growing
  windows from one byte on (amended after the review: a pipe that pauses
  after a short first record must not hold it back) until the format is
  clear, or the end.
- A document that is not MARC raises `Metacrunch::InputError` with its name:
  `dump.dat: is neither MARCXML, ISO 2709 nor MARC-in-JSON: it starts with
  "id;title;..."`; a JSON array: `records.json: is a JSON array of records;
  convert it to one record per line first, e.g. jq -c '.[]' in.json >
  out.jsonl`. This replaces the "is not XML" check of metacrunch-marcxml.
- `parse: true` yields `Record`s; a record that fails to parse is yielded as
  `Metacrunch::InvalidRecord` (raw: the record String, error: the
  `ParseError`), and the records after it are read. `parse: false` yields the
  raw Strings of `each_raw`.
- `normalize:` is nil or `:nfc` and needs `parse: true`, as now.
- `progress` is `Metacrunch::Input#progress`; without a block `each` returns
  an Enumerator.
- `id:` of `source` gets the record or the raw String.

## 9. Sink: `Metacrunch::Marc::Writer`

```ruby
Metacrunch::Marc::Writer.new(target, format:, oversize: nil)
```

- `target`: what `Metacrunch::Output` takes (`.gz` compresses, refused names,
  `"-"`, IOs).
- `format:` is required: `:xml`, `:iso2709` or `:json`; others raise
  `ArgumentError: format must be :xml, :iso2709 or :json, got :marc`.
- `oversize:` is `:error` (nil means `:error`) or `:allow`, for `:iso2709`
  only; given with another format it raises `ArgumentError`.

| Format | Output | Strings written as they are |
|---|---|---|
| `:xml` | `<?xml ...?>`, `<collection xmlns=...>`, the records indented, `</collection>` (also after an aborted run) | start with a `<record>` element (any prefix), as now |
| `:iso2709` | the records back to back | start with 5 digits and end with `0x1D` |
| `:json` | one line per record | start with `{` (after whitespace) and contain no line break but a last one; `"\n"` is appended if missing |

- A `Record` is serialized with the format's serializer; a `SerializeError`
  stops the run with `Metacrunch::Error`: `record at position 17 cannot be
  written as ISO 2709: field 852H: ...`.
- Any other object, or a String that does not fit the format, stops the run
  with the record's position: `record at position 17 is a String but not an
  ISO 2709 record`, `record at position 17 is not a Metacrunch::Marc::Record
  (Hash)`. Hashes belong in `Metacrunch::JsonLines::Writer`.
- `open`, `write`, `write_batch` and `close` as now; `close` writes the XML
  footer also after an aborted run and closes the output; a second `close`
  does nothing.

## 10. Workers and examples

`--workers` sends records between processes with Marshal; raw Strings cost a
fraction of parsed records. The fast path works for every format:

```ruby
source Metacrunch::Marc::Reader.new(params.files, parse: false)
map(name: "parse") { Metacrunch::Marc.parse(it) }
# ... steps ...
map(name: "serialize") { it.to_iso2709 }   # or it.to_xml(namespace: false), it.to_json
sink Metacrunch::Marc::Writer.new(params.target, format: :iso2709)
```

Serializing in a step also lets a record that cannot be written fail alone
under the job's failure policy, instead of stopping the run in the sink.

Examples:

- `examples/marc2jsonl.rb` (was `marcxml2jsonl.rb`): any format to a flat
  JSON Lines record.
- `examples/cleanup.rb`: as now, with `--to` (default `xml`) for the output
  format.
- `examples/convert.rb`: any format in, `--to xml|iso2709|json` out, with
  only the parse and serialize steps (workers-ready).
- `examples/data/catalog.xml`, `catalog.mrc`, `catalog.jsonl`: the same
  records in the three formats.

The examples pass `format: params.to.to_sym`; the Writer's `ArgumentError`
lists the valid formats.

## 11. Tests

Minitest, as now; every test file exercises one unit, plus integration tests
for jobs and examples.

### 11.1 Moved tests

The 210 tests of metacrunch-marcxml move with the renames of section 2; the
Reader test for a document that is not XML becomes a detection test.

### 11.2 Fixtures

Each XML fixture gets an `.mrc` and a `.jsonl` twin with the same records,
written once by the new serializers and checked against ruby-marc (11.5).
`local.xml` (tag `852H`, codes `as` and `dl`) cannot be written as ISO 2709
and gets only a `.jsonl` twin; it is the fixture for that refusal.
Broken ISO 2709 inputs are built in the tests from valid records, so each
test shows its defect.

### 11.3 Unit tests

- ISO 2709 reading: wrong record length; directory lengths counted in
  characters; decreasing starts; a start that is not a number; piece count
  above and below the entry count; a missing last `0x1E`; CR, LF, space and
  NUL between records; a cut last record; a leader shorter than 24 bytes or
  not ASCII; a tag that is not ASCII; MARC-8 with non-ASCII bytes (the hint)
  and with ASCII only (read); `FMT` as a control field; a `00X` data field;
  indicators other than two characters; an empty code; a code with a
  multibyte character; empty values; control characters (common rule);
  `normalize: :nfc`; a record with `99999` and one with `00000` as its length;
  `parse` with none, one and two records.
- ISO 2709 writing: leader positions computed and `record.leader` unchanged;
  a record without a leader; position 23 kept; each `SerializeError`;
  `oversize: :error` and `:allow` for a long field and a long record, read
  back; transcoding of non-UTF-8 values.
- MARC-in-JSON: `from_h` for every shape of 3.4 and every error with its
  path; duplicate keys; invalid UTF-8; blank lines and BOMs; a JSON array;
  the common rule when writing; `normalize: :nfc`.
- Detection: each row of the table in 7, for files, gzip, a tar archive with
  all three formats, stdin and a slow pipe; `Marc.parse` for each format and
  each error.
- Writer: each format, Strings per format accepted and refused, other objects
  refused, `format:` and `oversize:` arguments, the XML footer after an
  aborted run, `.gz`.

### 11.4 Round trips

Every fixture through all nine pairs of input and output format (`local.xml`
through the four without ISO 2709): the fields are equal, and so is the leader except the positions of 3.3 when ISO 2709 is
written; `type` is equal only from MARCXML to MARCXML.

### 11.5 Interop with ruby-marc 1.4

- `record.to_iso2709` equals ruby-marc's `to_marc` byte for byte for the
  fixtures (whose leaders already have `a` at 09, `22` at 10–11 and `4500` at
  20–23, the positions ruby-marc does not compute).
- Reading the same `.mrc` with `MARC::Reader` (`external_encoding: "UTF-8"`),
  ruby-marc's `to_hash` equals our `to_h`.

### 11.6 Jobs

Jobs MARCXML to ISO 2709, ISO 2709 to MARCXML and MARC-in-JSON to ISO 2709,
each with and without `workers: 2` and with `parse: true` and `parse: false`
(with the parse step of 10), give byte-identical output. With the serialize
step of 10 in the workers, ISO 2709 and MARC-in-JSON output is byte-identical
too and MARCXML output has the same records. An invalid record in each input
format fails alone under the failure policy, and so does a record that ISO
2709 cannot hold when it is serialized in a step.

## 12. Benchmarks

`bench/parse.rb` adds, per format: `parse` of one record String, `each_raw`
and `each` from a file, the serializer, and the Reader from a file and from a
gzip file. The synthetic records stay (about 3 KB as MARCXML). Targets in 1.3.

## 13. Documentation

- Readme, in this order: intro (the three formats; MARC 21 is a format, ISO
  2709 its binary syntax, MARCXML and MARC-in-JSON other syntaxes, in two
  sentences); installation; Records (querying, changing, output, unchanged);
  Formats with one subsection each (API, rules, limits, not supported);
  In metacrunch jobs (Reader, detection, Writer, workers, testing jobs);
  Upgrading from metacrunch-marcxml 4.x; license.
- The sentence about records cut off by the end of a file says what the code
  does (1.5).
- CHANGELOG: 1.0.0 (unreleased), successor of metacrunch-marcxml; the
  breaking changes and new features of the metacrunch-marcxml 5 changelog plus
  the new formats.
- Code comments and examples stay generic (no names of internal systems).

## 14. Deferred

- MARC-8 decoding (LC's tables, about 16,000 mappings).
- MarcEdit's mnemonic format `.mrk` (`to_s` is close already).
- A `format:` override on the Reader for documents the detection refuses.
- Continued fields in ISO 2709, indicator counts other than 2.
- JSON arrays of records.
- A MARCspec query language; OAI-PMH harvesting; matching `record` by
  namespace in MARCXML (from the metacrunch-marcxml spec).

## 15. Steps outside the code

- The user renames `ubpb/metacrunch-marcxml` to `ubpb/metacrunch-marc` on
  GitHub; GitHub redirects the old URLs, and the remote of local checkouts can
  be updated with `git remote set-url origin git@github.com:ubpb/metacrunch-marc.git`.
- Optionally the local checkout is renamed from `metacrunch-marcxml` to
  `metacrunch-marc`; the Gemfile's `METACRUNCH_PATH` default (`../metacrunch`)
  is not affected.
- metacrunch-marcxml on rubygems.org gets no further release.
