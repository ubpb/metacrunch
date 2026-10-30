# Files

Sources and sinks that read or write files can leave opening, decompressing and the details of stdin, stdout and pipes
to two building blocks: `Metacrunch::Input` and `Metacrunch::Output`. `JsonLines::Reader` and `JsonLines::Writer` are
built on them, and so are the sources and sinks that `metacrunch generate` creates and those of the extension gems
`metacrunch-marc`, `metacrunch-csv` and `metacrunch-xlsx`.

## Reading: `Metacrunch::Input`

```ruby
input = Metacrunch::Input.new(params.files)     # a path, "-", an IO, or an Array of them
input.each_document do |stream, name|
  stream.each_line { |line| ... }               # or read, readpartial, peek, eof?
end
input.progress                                  # 0.0 to 1.0, or nil
```

A target is a path (String or Pathname), `"-"` for stdin or an IO (anything with `readpartial` or `read`), or an
Array of them, read in order. `new` only checks the types; nothing is opened before `each_document`. Directories and
glob patterns are no targets: pass `Dir.glob(root.join("data/*.jsonl.gz")).sort` to choose files and their order.

`each_document` yields one stream per document: a plain or gzip file is one document, a tar or zip archive one per
file in it. The stream's methods return binary Strings; the format sets the encoding
(`line.force_encoding(Encoding::UTF_8)`). A stream is valid until the next document. `name` labels the document in
messages: the path as given, `-` for stdin, `dump.tar.gz:records/0001.xml` or `export.zip:data/titles.csv` for a file
in an archive.

### What is unpacked

The first bytes decide, not the name, for files, stdin and IOs alike:

| Content | |
|---|---|
| gzip | All members are read, as `zcat` reads files written with `cat a.gz b.gz` |
| tar | Every regular member; directories, links and members whose names start with `.` (such as the `._name` files of macOS `tar`) are skipped |
| zip | Every file, in the order of the archive's directory; directories, links and files whose names start with `.` (such as the `__MACOSX/._name` files of macOS) are skipped |
| bzip2, xz, zstd | An error that names the format and the command to decompress it first, e.g. `zstd -dc dump.jsonl.zst \| metacrunch run job.rb -i -` |
| anything else | The document as it is |

Unpacked content is checked again, so `.tar.gz`, a tar of `.gz` files, a zip of `.gz` files, a zip inside a `.tar.gz`
and gzip inside gzip work, up to 4 layers. On a slow pipe, detection does not hold back the first line of a
line-based format such as JSON Lines.

Input unpacks, but does not judge what it unpacks: whether a document suits the source is up to whoever chooses the
input. A source reads every document in its format, so a `readme.txt` in a zip of CSV files is read as CSV, as it
would be when given directly. Excel, Word, PowerPoint, OpenDocument and EPUB files are zip archives too, and are
unpacked like any other: their XML parts become documents. Give a job the files it is meant for, and unpack archives
with other files first.

A zip archive keeps its directory at its end, so it is read with random access:
- a file, or an IO that can seek (an open File, a StringIO, from its position), directly;
- stdin, a pipe, a FIFO and a zip archive inside gzip, tar or zip through an anonymous temporary file in
  `Dir.tmpdir` (which `TMPDIR` sets). The copy needs disk space for the archive. It has no name in the directory, so
  its space is freed when the archive is done or the process ends, however it ends.

### Errors

Every problem with a target raises `Metacrunch::InputError` with the name first, and stops the job like any error of a
source; records read before are already on their way:

```
data/b.jsonl: no such file
dump.jsonl.gz: broken gzip data (invalid compressed data -- format violated)
dump.jsonl.gz: data after the end of the gzip data
dump.tar.gz:records/7.xml: broken tar archive (ends inside the member's data)
export.zip:data/titles.csv: broken zip archive (wrong CRC32)
export.zip:data/titles.csv: is encrypted, which metacrunch cannot read; decrypt it first, e.g. 7z x export.zip
-: no space left on device for a temporary copy in /tmp (TMPDIR)
```

All paths are checked before the first document, so a typo in the last of several files ends the run before anything
is read. gzip files that end too early and tar archives that end inside a member or a header, an interrupted download
for example, are errors, not shorter data, and so are wrong gzip CRCs and tar header checksums. A tar archive that ends
exactly between two members cannot be told from a complete one, since its end marker is optional; it is read as it
is, as `tar` reads it.

A zip archive is checked as strictly: a wrong CRC32 or size, a truncated archive, a broken directory and files that
share data (a trick of zip bombs) are errors. Bytes after the end of an archive are accepted, as `unzip` accepts them.
An archive with files that are encrypted or compressed with a method other than stored or deflate (Deflate64, bzip2,
LZMA, zstd, xz, PPMd) is refused before its first document, with a hint to unpack it with 7z. A file read only in
part is still read to its end and checked, as a tar member is.

The hint for a format metacrunch cannot read names the command with the file (quoted for the shell) when the format is
the file's outer layer, a pipe for stdin, and only the tool for IOs and for documents inside gzip, tar or zip.

### Progress

With only regular files as targets, `progress` is the share of their bytes read so far (for gzip, of the compressed
bytes; for zip, up to the data read), counted in blocks of 64 KiB. A source that returns it from its own `progress`
method feeds the progress display of `metacrunch run`. With stdin, an IO or a FIFO among the targets it is `nil`.

### Known limits

- Member names longer than the fields of a tar header (stored in pax records) appear shortened in messages; the data
  is read in full.
- Old tar archives without the `ustar` mark (v7) are read as plain content.
- GNU sparse members of a tar archive are skipped.
- Members larger than 8 GiB, whose size tar stores in binary, raise an error.
- zip archives: only stored and deflated files, no encryption and no split archives (`.z01`, ...). Data before an
  archive (a self-extracting archive) is not read as zip.
- File names in a zip archive are read as UTF-8, else as CP437, the code page of MS-DOS. Names written in other code
  pages (CP850, CP866, CP932) appear wrongly in messages; the data is not affected.
- A zip archive whose writer stored a size off by exactly 4 GiB, a bug of some writers, raises an error.
- For a zip archive inside gzip or tar, progress moves on while the archive is copied, and then stands still while
  its documents are read.

### A source on `Input`

```ruby
class Lines

  def initialize(targets)
    @input = Metacrunch::Input.new(targets)
  end

  def each
    @input.each_document do |stream, _name|
      stream.each_line { |line| yield({"line" => line.chomp.force_encoding(Encoding::UTF_8)}) }
    end
  end

  def progress = @input.progress

end
```

## Writing: `Metacrunch::Output`

```ruby
output = Metacrunch::Output.new(params.output)  # a path, "-" for stdout, or an IO
output.open                                     # creates or truncates the file
output.write(string)
output.flush                                    # writes what Ruby buffers, e.g. for a source that waits
output.close
```

A path ending with `.gz` is written with gzip. Names ending with `.bz2`, `.xz`, `.zst`, `.zip`, `.tar`, `.tar.gz` or
`.tgz` are refused before a file is created, since the content would not match the name; write plain output and pipe
it into the compressor. Existing files are overwritten.

When the reader of a pipe goes away (`metacrunch run job.rb | head`), `write` raises `SignalException("PIPE")` once,
and the run ends as if by SIGPIPE; later writes do nothing. `close` closes files the output opened and only flushes
`$stdout` and IOs from outside. `flush` writes what Ruby buffers to the file or stream, a gzip file with a sync flush,
so a reader of the file sees whole lines so far. Other problems raise `Metacrunch::OutputError` with the name first,
such as `out/x.jsonl: no such directory` or `out.jsonl: no space left on device`.

### A sink on `Output`

```ruby
class JsonFile

  def initialize(target)
    @output = Metacrunch::Output.new(target)
  end

  def open(_context) = @output.open

  def write(record)
    @output.write("#{JSON.generate(record)}\n")
  end

  def flush = @output.flush

  def close = @output.close

end
```
