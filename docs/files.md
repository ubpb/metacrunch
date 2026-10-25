# Files

Sources and sinks that read or write files can leave opening, decompressing and the details of stdin, stdout and pipes
to two building blocks: `Metacrunch::Input` and `Metacrunch::Output`. `JsonLines::Reader` and `JsonLines::Writer` are
built on them, and so are the sources and sinks that `metacrunch generate` creates.

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

`each_document` yields one stream per document: a plain or gzip file is one document, a tar archive one per regular
member. The stream's methods return binary Strings; the format sets the encoding
(`line.force_encoding(Encoding::UTF_8)`). A stream is valid until the next document. `name` labels the document in
messages: the path as given, `-` for stdin, `dump.tar.gz:records/0001.xml` for a member.

### What is unpacked

The first bytes decide, not the name, for files, stdin and IOs alike:

| Content | |
|---|---|
| gzip | All members are read, as `zcat` reads files written with `cat a.gz b.gz` |
| tar | Every regular member; directories, links and members whose names start with `.` (such as the `._name` files of macOS `tar`) are skipped |
| bzip2, xz, zstd, zip | An error that names the format and the command to decompress it first, e.g. `zstd -dc dump.jsonl.zst \| metacrunch run job.rb -i -` |
| anything else | The document as it is |

Unpacked content is checked again, so `.tar.gz`, a tar of `.gz` files and gzip inside gzip work, up to 4 layers. On
a slow pipe, detection does not hold back the first line of a line-based format such as JSON Lines.

### Errors

Every problem with a target raises `Metacrunch::InputError` with the name first, and stops the job like any error of a
source; records read before are already on their way:

```
data/b.jsonl: no such file
dump.jsonl.gz: broken gzip data (invalid compressed data -- format violated)
dump.jsonl.gz: data after the end of the gzip data
dump.tar.gz:records/7.xml: broken tar archive (ends inside the member's data)
```

All paths are checked before the first document, so a typo in the last of several files ends the run before anything
is read. gzip files that end too early and tar archives that end inside a member or a header, an interrupted download
for example, are errors, not shorter data, and so are wrong gzip CRCs and tar header checksums. A tar archive that ends
exactly between two members cannot be told from a complete one, since its end marker is optional; it is read as it
is, as `tar` reads it.

The hint for a format metacrunch cannot read names the command with the file (quoted for the shell) when the format is
the file's outer layer, a pipe for stdin, and only the tool for IOs and for documents inside gzip or tar.

### Progress

With only regular files as targets, `progress` is the share of their bytes read so far (for gzip, of the compressed
bytes), counted in blocks of 64 KiB. A source that returns it from its own `progress` method feeds the progress display
of `metacrunch run`. With stdin, an IO or a FIFO among the targets it is `nil`.

### Known limits

- Member names longer than the fields of a tar header (stored in pax records) appear shortened in messages; the data
  is read in full.
- Old tar archives without the `ustar` mark (v7) are read as plain content.
- GNU sparse members of a tar archive are skipped.
- Members larger than 8 GiB, whose size tar stores in binary, raise an error.

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
output.close
```

A path ending with `.gz` is written with gzip. Names ending with `.bz2`, `.xz`, `.zst`, `.zip`, `.tar`, `.tar.gz` or
`.tgz` are refused before a file is created, since the content would not match the name; write plain output and pipe
it into the compressor. Existing files are overwritten.

When the reader of a pipe goes away (`metacrunch run job.rb | head`), `write` raises `SignalException("PIPE")` once,
and the run ends as if by SIGPIPE; later writes do nothing. `close` closes files the output opened and only flushes
`$stdout` and IOs from outside. Other problems raise `Metacrunch::OutputError` with the name first, such as
`out/x.jsonl: no such directory` or `out.jsonl: no space left on device`.

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

  def close = @output.close

end
```
