# 2. Read ZIP archives without a ZIP library

- Status: accepted
- Date: 2026-10-29

## Context

Data portals, publishers and libraries deliver CSV, XML and N-Triples as ZIP archives; the Library of Congress, for
example, offers `externallinks.nt.zip` from id.loc.gov. `Metacrunch::Input` read gzip and tar, but refused ZIP and
pointed to `unzip -p`, which joins all entries into one stream. A CSV reader then reads the header row of the second
file as data, and two XML documents in a row are no longer one document. Input should read ZIP as it reads tar: one
document per file, as strict as it is with gzip and tar, without a new runtime dependency where one can be avoided.

The candidate library was zip_kit, which metacrunch-xlsx already uses to write workbooks. Its reader parses the
structure of an archive (end record, Zip64, central directory, local headers) in about 250 lines. It does not check
CRCs or sizes, and it ignores encryption flags, name encodings and file types. A throwaway reader on Ruby's `zlib`
was checked against Python's `zipfile` on 265 archives with 75,157 files: writers on a local machine, the ZIP test
data of Go, libarchive and CPython (WinZip, WinRAR, 7-Zip, Windows, macOS), real deliveries and a 4.5 GiB Zip64 file.
Wherever both read an entry, it gave the same data. Both readers then read 21,000 mutated archives:

| | Own reader | zip_kit |
|---|---|---|
| Crashes (RangeError, NoMethodError) | 0 | 23 |
| Endless read loops | 0 | 275 |
| Silently wrong data | 0 | 4,155 |

## Decision

The core reads ZIP with its own reader, `Metacrunch::Input::Zip`, on `zlib` from the standard library. It reads stored
and deflated entries and checks every entry's size and CRC32. Truncated archives, a broken directory and overlapping
entries are errors. It is tolerant where unzip, Python, Go and libarchive are: bytes after the archive, padding in
extra fields, MS-DOS directories, names without the UTF-8 flag (CP437), and more than 65,535 entries without Zip64.
Encrypted entries, other methods and split archives are refused with a hint. The reader is internal; metacrunch's
own gems may use it, for example to read the parts of a workbook.

## Alternatives

- zip_kit: the structure is the smaller part of the work. Its reader would still need the CRC and size checks, the
  checks of names and types, and guards against its endless loops and crashes, so it would save little and add a
  dependency to the core.
- rubyzip: a larger dependency for the same job.
- `unzip -p` as before: entries lose their boundaries.

## Consequences

- About 300 lines of code to maintain in the core (the reader and Input's checks), guarded by a test builder that
  writes archives byte by byte, archives of other writers from Go's test data, and a fuzz test.
- Only stored and deflate: Ruby's standard library has no Deflate64, bzip2, LZMA or zstd. Such archives need 7z
  first.
- An archive needs random access, since its directory is at its end: stdin, pipes and archives inside gzip are copied
  into a temporary file first.
- Input unpacks a zip archive like any other when `:zip` is in `unpack:`, also a ZIP-based format such as an Office,
  OpenDocument or EPUB file, whose parts then become documents. A reader for such a format leaves `:zip` out of
  `unpack:`, so it gets the file as a document, or uses the ZIP reader directly.
