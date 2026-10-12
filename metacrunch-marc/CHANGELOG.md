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
