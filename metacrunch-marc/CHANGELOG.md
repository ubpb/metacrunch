# Changelog

## 5.0.0 (unreleased)

The successor of metacrunch-marcxml, rewritten for metacrunch 5: MARCXML, ISO 2709 and MARC-in-JSON on one record
model. Code written for metacrunch-marcxml 4.x must be adapted; see the Readme.

It lives in the metacrunch repository, shares metacrunch's version and requires metacrunch in exactly that version.

### Breaking changes (from metacrunch-marcxml 4.x)

- The gem is `metacrunch-marc` (`require "metacrunch/marc"`) and the namespace `Metacrunch::Marc`; MARCXML is read by
  `Metacrunch::Marc::Xml`.
- Requires Ruby 4.0 and metacrunch 5. ActiveSupport is no longer a dependency.
- `Metacrunch::Marc::Xml.parse` returns exactly one record and raises `ParseError` otherwise; `collection_mode:` and
  `Metacrunch.Marcxml(...)` are gone. `Metacrunch::Marc::Xml.each` streams the records of a collection.
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
- Values must be valid UTF-8 without characters that XML 1.0 cannot represent; others raise `ParseError`.

### New

- ISO 2709 in UTF-8: `Metacrunch::Marc::Iso2709.parse`, `.each` and `.each_raw`, and `Record#to_iso2709` with
  `oversize:`. Reading trusts the terminators, so records with wrong lengths and records over 99,999 bytes are read;
  MARC-8 records fail with a hint to convert them.
- MARC-in-JSON, one record per line: `Metacrunch::Marc::Json.parse`, `.each` and `.each_raw`, `Record#to_json` and
  `Record.from_h`.
- `Metacrunch::Marc.parse` reads one record in any of the three formats.
- `Metacrunch::Marc::Reader`, a source on `Metacrunch::Input`: all three formats, told by the content of each
  document; files, gzip files (also with several members) and tar archives recognized by their content, stdin and
  IOs. A record that cannot be read becomes a `Metacrunch::InvalidRecord`; a document in another format or a
  truncated gzip or tar file raises `Metacrunch::InputError`.
- `Metacrunch::Marc::Writer`, a sink on `Metacrunch::Output` with `format:` (`:xml`, `:iso2709` or `:json`), for
  `Record`s and for record Strings serialized in a worker.
- `Record#to_xml`, `#to_h` (MARC-in-JSON) and `#to_s` (MarcEdit's mnemonic form, also used by `inspect`).
- Changing records: `Record#add`, `#append`, `#remove` (also with a block), `#clear`, `DataField#add`, `#remove`, deep
  `dup`. The fields of a record are a frozen Array and the tag of a field is fixed, so queries by tag use an index.
- `each_raw` for every format, and `normalize: :nfc`.
