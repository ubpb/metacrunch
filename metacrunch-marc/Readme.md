# metacrunch-marc

MARC for [metacrunch](https://github.com/ubpb/metacrunch): one ordered record model with a plain Ruby API, parsers
that keep the data as written and serializers for MARCXML, ISO 2709 and MARC-in-JSON, and a source and a sink for
metacrunch jobs. MARC 21 is the format of the records; ISO 2709 ("binary MARC", `.mrc`) is its traditional exchange
syntax, and MARCXML and MARC-in-JSON carry the same records as XML and JSON.

```ruby
require "metacrunch/marc"

Metacrunch.job do
  params { args :files, min: 1 }

  source Metacrunch::Marc::Reader.new(params.files), id: ->(record) { record["001"]&.value }

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
$ metacrunch run jobs/marc2jsonl.rb records.mrc more-records.xml.gz > records.jsonl
```

The reader tells the format of each file by its content, so the same job reads all three formats. More in
[`examples/`](examples): MARC to JSON Lines, a cleanup job, and a converter between the formats.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-marc"
end
```

Requires Ruby 4.0 and metacrunch in the same version as this gem. The only other dependency is
[Ox](https://github.com/ohler55/ox), for MARCXML.

## Records

A `Metacrunch::Marc::Record` has a `leader` (a String or nil), a `type` (the `type` attribute of a MARCXML
`<record>`, e.g. `"Bibliographic"`, or nil) and `fields`, a frozen Array of `ControlField`s and `DataField`s in record
order. A `DataField` has a `tag`, two indicators (`ind1`, `ind2`; blank is `" "`) and `subfields`, an Array of
`Subfield`s with a `code` and a `value`. Tags and codes are Strings and are not checked, so local tags such as `852H`
and codes such as `as` work in the formats that can hold them (see [Formats](#formats)). The tag of a field is fixed.

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

`fields` without arguments returns the record's frozen Array, `subfields` without arguments the field's own Array; a
query with arguments returns a new Array. Results are plain Arrays, so they chain with `flat_map`, `filter_map` and
friends: `record.fields("856", ind1: "4").flat_map { it.values("u") }`.

A query by one tag uses an index of the record's fields, built on the first query after a change, so it costs about
the same however many fields a record has: eight typical queries take about 1.5 µs per record in `bench/parse.rb`.

### Changing

```ruby
record.add(Metacrunch::Marc::DataField.new("650", " ", "7", [["a", "Linked data"], ["2", "gnd"]]))
record.append(Metacrunch::Marc::ControlField.new("009", "x"))
record.remove("856", ind1: "4", ind2: "2")        # returns the removed fields
record.remove { it.tag.start_with?("9") }         # with a block, also with tags and indicators
record.clear                                      # removes all fields and returns them
field.add("a", "Value")                           # appends a subfield
field.remove("x")                                 # returns the removed subfields
field.ind1 = "1"
copy = record.dup                                 # a deep copy
```

The fields of a record change only through `add`, `append`, `remove` and `clear`, which keep the index right;
`record.fields << field` raises `FrozenError`. `add` inserts a field before the first field whose tag sorts after its
tag; `append` adds it at the end. `remove` needs a tag, an indicator filter or a block (a code for `field.remove`), so
an empty list cannot clear a record by accident; `record.clear` and `field.subfields.clear` remove everything. Codes,
like tags, may also come in an Array: `field.values(["a", "b"])`.

The tag of a field cannot change. To move a field to another tag, add a new field and remove the old one:

```ruby
record.add(Metacrunch::Marc::DataField.new("690", field.ind1, field.ind2, field.subfields))
record.remove { it.equal?(field) }
```

### Output

- `record.to_xml` returns the record as MARCXML; `namespace: false` leaves out `xmlns`.
- `record.to_iso2709` returns it as ISO 2709, binary MARC as in `.mrc` files (ruby-marc's `to_marc`), a String in
  UTF-8 (see [ISO 2709](#iso-2709)).
- `record.to_json` returns it as one line of MARC-in-JSON (see [MARC-in-JSON](#marc-in-json)); `JSON.generate` uses it
  for records inside other values.
- `record.to_h` returns MARC-in-JSON: `{"leader" => "...", "fields" => [{"001" => "..."}, {"245" => {"ind1" => "1",
  "ind2" => "0", "subfields" => [{"a" => "..."}]}}]}`; `Metacrunch::Marc::Record.from_h(hash)` builds a record from
  such a Hash.
- `record.to_s` and `inspect` show one line per field as MarcEdit does (`=245  10$aTitle$bSubtitle`), so records are
  readable in `metacrunch trace` and in test failures.

## Formats

```ruby
Metacrunch::Marc.parse(string)                            # one record in any format, told by its first bytes
Metacrunch::Marc.each(io_or_string) { ... }               # every record in any format, streaming

Metacrunch::Marc::Iso2709.parse(string)                   # one record, ISO 2709 only
Metacrunch::Marc::Iso2709.each(io_or_string) { ... }      # every record, streaming
Metacrunch::Marc::Iso2709.each_raw(io_or_string) { ... }  # every record as a String, without parsing it
# the same for Metacrunch::Marc::Xml and Metacrunch::Marc::Json
```

`Metacrunch::Marc.parse` reads a record whatever its format, e.g. the Strings the [Reader](#reader) yields with
`parse: false`. `Metacrunch::Marc.each` streams a document whatever its format, for code outside a job: unlike the
[Reader](#reader) it reads one String or IO-like object, takes no paths, unpacks no gzip or tar and raises at the
first record it cannot read. The format modules read their format only, so input in another format fails, and they
also stream.

`each` and `each_raw` read Strings and IO-like objects (files, `StringIO`, `Zlib::GzipReader`, pipes); without a block
they return an Enumerator. They read in chunks, so the time grows in proportion to the input. `parse` raises
`Metacrunch::Marc::ParseError` for no record or several, and `each` at the first record it cannot read (the
[Reader](#reader) makes such a record a failure of its own). With `normalize: :nfc` the leader and the values are
normalized to Unicode NFC (some systems export decomposed characters); by default they are left as they are.

All parsers and serializers keep to one rule, so whatever one format reads, the others can write: the leader, tags,
indicators, codes and values are valid UTF-8 and contain no character that XML 1.0 cannot represent (control
characters other than tab and line breaks, U+FFFE and U+FFFF). Parsers raise `ParseError` and serializers
`Metacrunch::Marc::SerializeError`, naming the field: `field 245 $a: "\u0001" cannot be represented in XML 1.0`.
Serializers transcode Strings in other encodings and take binary Strings as UTF-8.

What each format can hold:

| | MARCXML | ISO 2709 | MARC-in-JSON |
|---|---|---|---|
| Tags | any | 3 ASCII characters | any |
| Indicators and codes | any | 1 ASCII character | any |
| Data field without subfields | yes | no (it would be read back as a control field) | yes |
| `type` | yes | no | no |
| Size | no limit | 9,999 bytes per field, 99,999 per record | no limit |

### MARCXML

Parsing takes about 29 µs per record of 3 KB in [`bench/parse.rb`](bench/parse.rb) (Ruby 4.0 with YJIT on an arm64
Mac); the time grows with the size of the records, by about 10 µs per KB. The parser keeps what the data says:

- whitespace at the start, at the end and inside values, and line breaks (XML itself turns `\r\n` into `\n`);
- the order of fields and subfields, repeated control fields, empty subfields;
- CDATA, entities, and values interrupted by comments;
- elements with a namespace prefix (`<marc:record>`), the `type` attribute, and a leader anywhere in the record.

A missing or empty indicator becomes `" "`. `ParseError` reports input that is not well-formed (with `line` and
`column`), input that ends inside a record, NUL bytes (with their offset; Ox would take one for the end of the input),
names and attributes that are not valid UTF-8 (MARCXML is UTF-8), and values that break the rule above, also as
references such as `&#31;`. Several records without a `<collection>` around them, and NUL bytes outside records, are
not well-formed XML for `each`; `each_raw` and the Reader read them. Ox, the XML parser underneath, does not
validate and accepts some input that is not well-formed; a reference `&#0;`, which XML does not allow, cuts the value
off there.

`each_raw` cuts the input at the end tags of the records; an end tag inside a CDATA section or a comment cuts a record
there. Elements are matched by their local name, whatever their namespace. Formats that wrap MARCXML in an element of
their own called `record`, such as OAI-PMH responses (`ListRecords`), are therefore not read correctly yet; take the
MARC records out of the wrapper first.

### ISO 2709

ISO 2709 is the exchange format of MARC 21 known as binary MARC: the `.mrc` files, which ruby-marc writes with
`to_marc` and this gem with `to_iso2709`. It is read and written in UTF-8. Parsing takes about 12 µs and writing about
6 µs per record in `bench/parse.rb` (records of 3 KB as MARCXML are 1.2 KB as ISO 2709).

Reading trusts the terminators, not the numbers, as yaz-marcdump and MARC4J's permissive reader do:

- A record runs to its record terminator. The record length, the base address and the field lengths are not used, so
  records with wrong lengths, with lengths counted in characters, and records over 99,999 bytes with `99999` or
  `00000` as their length are read. Line breaks, spaces, tabs and NUL between records are skipped, and so are the byte
  order marks of concatenated files.
- The directory runs to the first field terminator; the data is split on field terminators, and the nth field belongs
  to the nth directory entry. Another number of fields than of entries, starts that are not five digits or that
  decrease (data in another order than the directory), a leader or a tag that is not ASCII, and indicators other than
  two characters raise `ParseError`.
- A field with a subfield delimiter is a data field, any other a control field, so local control fields such as `FMT`
  are read right. Indicators and codes are read as characters.
- Bytes are read as UTF-8, whatever leader/09 says. MARC-8 records in plain ASCII are read; others fail with a hint:
  `leader/09 says MARC-8; convert the file to UTF-8 first, e.g. yaz-marcdump -f MARC-8 -t UTF-8 -o marc -l 9=97
  in.mrc > out.mrc`.

`to_iso2709` writes the fields in record order, counts lengths in bytes and fills the leader positions it computes:
00–04 (record length), 09 (`a`, UTF-8), 10–11 (`22`), 12–16 (base address) and 20–22 (`450`). It copies the others and
never changes `record.leader`; a record without a leader gets `00000    a2200000   4500`. A field over 9,999 bytes or
a record over 99,999 bytes raises `SerializeError`; with `oversize: :allow` the numbers that do not fit are written as
all nines, which tolerant readers (this one, MARC4J's permissive reader, yaz, Perl's MARC::Record) read and strict
readers do not.

Not supported: MARC-8 beyond ASCII, fields continued over several directory entries, indicator counts other than 2,
code lengths other than 1, and leaders that start with spaces (a blank record length): the spaces are taken for those
between records, and a file whose first record has no record length is not recognized as ISO 2709.

### MARC-in-JSON

[MARC-in-JSON](https://github.com/marc-in-json/marc-in-json) is `record.to_h` as JSON, which `record.to_json` writes
after the rule above (values that are not Strings as their `to_s`, nil as `""`). `each` and `each_raw` read one record
per line (JSON Lines), as ruby-marc and Catmandu do; blank lines and byte order marks are skipped. `parse` reads
one JSON object, also over several lines. Parsing takes about 33 µs per record in `bench/parse.rb`, most of it for
checking the shape and the values. JSON arrays of records are not read: convert them with
`jq -c '.[]' in.json > out.jsonl`, and pretty-printed files with `jq -c . in.json > out.jsonl`.

The shape is strict: keys are Strings; a field is an object with one key, its tag, whose value is a String (a control
field) or an object with `"ind1"`, `"ind2"` (missing or null is `" "`) and `"subfields"`, an Array of objects with one
key, the code. Anything else, and duplicate keys, raise `ParseError` with the path to the problem: `fields[3] (245)
subfields[0]: a value must be a String, got 12`. `Record.from_h` checks Hashes the same way.

## In metacrunch jobs

### Reader

```ruby
source Metacrunch::Marc::Reader.new(params.files, normalize: :nfc), id: ->(record) { record["001"]&.value }
```

Reads what `Metacrunch::Input` reads (see metacrunch's
[Files](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/files.md)): one target or an Array of them —
paths, `"-"` for stdin, or IOs, which it does not close. gzip (all members, as `zcat` reads them) and tar archives
(every regular member, but not those whose names start with `.`) are detected by their content, whatever their names.

The format of each document (a file, the content of a gzip file, a tar member) is told by its first bytes, after a
byte order mark and whitespace: `<` is MARCXML, `{` MARC-in-JSON, a record length and a base address (five digits at
00–04 and at 12–16) ISO 2709. So one run reads all three formats, also from one tar archive. A document that starts
otherwise stops the run with `Metacrunch::InputError` and its first bytes (`dump.dat: is neither MARCXML, ISO 2709 nor
MARC-in-JSON: it starts with "id;title;..."`), and so does a JSON array, with a hint to convert it. An empty document
gives no records.

A record that cannot be parsed becomes a `Metacrunch::InvalidRecord` and fails under the job's failure policy; the
records after it are read. So does a record that the end of a file cuts off, e.g. after an interrupted download.
Errors of a whole input (a missing file, broken or truncated gzip or tar data) stop the run with
`Metacrunch::InputError` and the file name. The progress display shows how much of the files has been read.

### Writer

```ruby
sink Metacrunch::Marc::Writer.new(params.target, format: :iso2709)   # :xml, :iso2709 or :json
```

Writes to a path (`.gz` compresses), `"-"` for stdout, or an IO. `:xml` writes one `<collection>` with a `<record>` per
record, and its closing tag also when a run aborts, so the file stays well-formed; `:iso2709` writes the records back
to back, `:json` one record per line. `oversize: :allow` (with `:iso2709` only) writes records beyond the limits of ISO
2709 as described above. Names ending with `.zst`, `.bz2`, `.xz`, `.zip`, `.tar`, `.tar.gz` or `.tgz` are refused; see
`Metacrunch::Output`.

Records are `Record`s or, serialized in a step, Strings of the format (see Workers): a `<record>` element, an ISO 2709
record, one line of JSON. A record that the format cannot hold (a tag such as `852H` in ISO 2709, a value set in a step
with a character that XML cannot represent) stops the run with the record's position; serialized in a step, it fails
alone under the job's failure policy instead.

### Workers

`--workers` sends records between processes with `Marshal`. A parsed record costs much more to send than its String:
in `bench/parse.rb`, 44 µs per record for a parsed record and about 1 µs for its String in any format. With workers,
let the reader yield Strings, parse them in the first step and serialize in the last:

```ruby
source Metacrunch::Marc::Reader.new(params.files, parse: false)
map(name: "parse") { Metacrunch::Marc.parse(it) }
# ... steps ...
map(name: "serialize") { it.to_iso2709 }   # or it.to_xml(namespace: false), it.to_json
sink Metacrunch::Marc::Writer.new(params.target, format: :iso2709)
```

`Metacrunch::Marc.parse` reads every format, so the job does not depend on its input. `id:` then gets the String. A
job that ends in Hashes needs no serialize step. In a MARC to MARC job with cheap steps and records of 3 KB as MARCXML,
4 workers handled about 21,000 records/s when they sent records back (as many as without workers) and about 64,000
records/s when they sent MARCXML back.

### Testing jobs

```ruby
records = Metacrunch::Marc::Xml.each(<<~XML).to_a
  <collection>
    <record><controlfield tag="001">1</controlfield></record>
  </collection>
XML
result = Metacrunch::Testing.run(job, source: records)
```

## Upgrading from metacrunch-marcxml 4.x

metacrunch-marc is the successor of metacrunch-marcxml. See the [changelog](CHANGELOG.md) for all changes. The most
common ones:

| metacrunch-marcxml 4.x | metacrunch-marc |
|---|---|
| `gem "metacrunch-marcxml"`, `require "metacrunch/marcxml"` | `gem "metacrunch-marc"`, `require "metacrunch/marc"` |
| `Metacrunch::Marcxml.parse(xml, collection_mode: true)` | `Metacrunch::Marc::Xml.each(xml).to_a` |
| `Metacrunch::Marcxml.parse(xml)` | `Metacrunch::Marc::Xml.parse(xml)` or `Metacrunch::Marc.parse(xml)` |
| `record.datafields("245", ind2: "0").subfields("a").values` | `record.values("245", "a", ind2: "0")` |
| `record["100**a"]` | `record.values("100", "a")` |
| `record.controlfield("001").value` | `record["001"]&.value` |
| `record.leader.value` | `record.leader` |
| `datafield.subfields("a").first&.value` | `datafield.value("a")` |
| `ind1: :blank` | `ind1: " "` |

## License

MIT; see [License.txt](License.txt).
