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
`"Bibliographic"`, or nil) and `fields`, a frozen Array of `ControlField`s and `DataField`s in document order. A
`DataField` has a `tag`, two indicators (`ind1`, `ind2`; blank is `" "`) and `subfields`, an Array of `Subfield`s
with a `code` and a `value`. Tags and codes are Strings and are not checked, so local tags such as `852H` and codes
such as `as` work. The tag of a field is fixed.

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
the same however many fields a record has: eight typical queries take about 2 µs per record in `bench/parse.rb`.

### Changing

```ruby
record.add(Metacrunch::Marcxml::DataField.new("650", " ", "7", [["a", "Linked data"], ["2", "gnd"]]))
record.append(Metacrunch::Marcxml::ControlField.new("009", "x"))
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
record.add(Metacrunch::Marcxml::DataField.new("690", field.ind1, field.ind2, field.subfields))
record.remove { it.equal?(field) }
```

### Output

- `record.to_xml` returns the record as MARCXML; `namespace: false` leaves out `xmlns`.
- `record.to_h` returns MARC-in-JSON: `{"leader" => "...", "fields" => [{"001" => "..."}, {"245" => {"ind1" => "1",
  "ind2" => "0", "subfields" => [{"a" => "..."}]}}]}`.
- `record.to_s` and `inspect` show one line per field as MarcEdit does (`=245  10$aTitle$bSubtitle`), so records are
  readable in `metacrunch trace` and in test failures.

## Parsing

```ruby
Metacrunch::Marcxml.parse(xml)                     # exactly one record from a String
Metacrunch::Marcxml.each(io_or_string) { ... }     # every record, streaming
Metacrunch::Marcxml.each_xml(io_or_string) { ... } # every record as a String, without parsing it
```

`each` and `each_xml` read Strings and IO-like objects (files, `StringIO`, `Zlib::GzipReader`, pipes); without a block
they return an Enumerator. All of them are read in chunks, so the time grows in proportion to the input. Parsing takes about
28 µs per record of 3 KB in [`bench/parse.rb`](bench/parse.rb) (Ruby 4.0 with YJIT on an arm64 Mac); the time grows
with the size of the records, by about 9 µs per KB.

The parser keeps what the data says:

- whitespace at the start, at the end and inside values, and line breaks (XML itself turns `\r\n` into `\n`);
- the order of fields and subfields, repeated control fields, empty subfields;
- CDATA, entities, and values interrupted by comments;
- elements with a namespace prefix (`<marc:record>`), the `type` attribute, and a leader anywhere in the record.

A missing or empty indicator becomes `" "`. With `normalize: :nfc` values are normalized to Unicode NFC (some systems
export decomposed characters); by default they are left as they are.

`Metacrunch::Marcxml::ParseError` reports input that is not well-formed (with `line` and `column`), input that ends
inside a record, values, names and attributes that are not valid UTF-8 (MARCXML is UTF-8), values with characters that
XML 1.0 cannot represent (control characters other than tab and line breaks, also as `&#31;`), and `parse` with no
record or several. Several
records without a `<collection>` around them are not well-formed XML for `each`; `each_xml` and the `Reader` read them.
Ox, the XML parser underneath, does not validate and accepts some input that is not well-formed; a reference `&#0;`,
which XML does not allow, cuts the value off there.

`each_xml` cuts the input at the end tags of the records; an end tag inside a CDATA section or a comment cuts a record
there.

Elements are matched by their local name, whatever their namespace. Formats that wrap MARCXML in an element of their
own called `record`, such as OAI-PMH responses (`ListRecords`), are therefore not read correctly yet; take the MARC
records out of the wrapper first.

## In metacrunch jobs

### Reader

```ruby
source Metacrunch::Marcxml::Reader.new(params.files, normalize: :nfc), id: ->(record) { record["001"]&.value }
```

Reads what `Metacrunch::Input` reads (see metacrunch's
[Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/docs/files.md)): one target or an Array of them —
paths, `"-"` for stdin, or IOs, which it does not close. gzip (all members, as `zcat` reads them) and tar archives
(every regular member, but not those whose names start with `.`) are detected by their content, whatever their names.
A record that is not well-formed becomes a `Metacrunch::InvalidRecord` and fails under the job's failure policy; the
records after it are read. A document that does not start like XML stops the run with `Metacrunch::InputError`, and
so does a record that the end of a file cuts off, e.g. after an interrupted download. Errors of a whole input (a
missing file, broken or truncated gzip or tar data) stop the run with `Metacrunch::InputError` and the file name. The
progress display shows how much of the files has been read.

### Writer

```ruby
sink Metacrunch::Marcxml::Writer.new(params.output)   # a path (".gz" compresses), "-" for stdout, or an IO
```

Writes one `<collection>` with a `<record>` per record; records are `Record`s or record XML as a String (see Workers). The closing tag is written also when a run aborts, so the file
stays well-formed. A value set in a step with a character that XML 1.0 cannot represent (a control character other
than tab and line breaks) stops the run with the record's position; records read with such a character are already
`InvalidRecord`s. Names ending with `.zst`, `.bz2`, `.xz`, `.zip` or `.tar` are refused; see `Metacrunch::Output`.

### Workers

`--workers` sends records between processes with `Marshal`. A parsed record costs much more to send than its XML: in
`bench/parse.rb`, 42 µs per record for a parsed record and 1 µs for its XML string. With workers, let the reader
yield the XML and parse it in the first step:

```ruby
source Metacrunch::Marcxml::Reader.new(params.files, parse: false)
map(name: "parse") { Metacrunch::Marcxml.parse(it) }
# ... steps ...
map(name: "serialize") { it.to_xml(namespace: false) }   # MARC to MARC: send XML back too
sink Metacrunch::Marcxml::Writer.new(params.output)
```

`id:` then gets the XML string. The writer writes a String that starts with a `<record>` element as it is, so a MARC
to MARC job can serialize in the workers as well; a job that ends in Hashes needs no last step. In a MARC to MARC job
with cheap steps and records of 3 KB, 4 workers handled about 21,000 records/s when they sent records back (as many as
without workers) and about 64,000 records/s when they sent XML back.

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
