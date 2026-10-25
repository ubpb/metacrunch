# metacrunch-ng, sub-project 11: IO layer

- Date: 2026-10-25 (brainstorming started 2026-10-23)
- Branch: `metacrunch-ng-io` (from `metacrunch-ng` at c7ae107); in
  metacrunch-marcxml a branch `metacrunch-ng-io` from its `metacrunch-ng`
  at ddb2e67
- Status: approved design, not implemented
- Builds on: [sub-project 2 spec](2026-10-10-metacrunch-ng-cli-pipes-design.md)
  (CLI, pipes, JSON Lines), [sub-project 9 spec](2026-10-18-metacrunch-ng-generators-design.md)
  (source and sink templates), the metacrunch-marcxml spec
  (`docs/superpowers/specs/2026-10-12-marcxml-ng-design.md` in that
  repository)

## 1. Context

The 4.x gem metacrunch-file had a `FileSource` that read plain files, gzip
files, tar archives and gzipped tar archives on the fly. metacrunch 5 has no
such gem yet, but the same work is done twice, slightly differently:

| | gzip | tar | several targets | gzip with several members | progress |
|---|---|---|---|---|---|
| `JsonLines::Reader` (core) | by name | no | no | yes (own `GzipMembers`, by line) | every 1024 lines |
| `Marcxml::Reader` (gem) | by name or content | by name | yes | yes (own `GzipMembers`, by block) | every 256 records, across targets |

`Marcxml::Writer` copies `guard`, `discard` and `output` of
`JsonLines::Writer` line by line: a closed pipe ends the run as SIGPIPE, IOs
from outside are flushed instead of closed, `.gz` is written with gzip.

This sub-project moves that work into one public layer in core,
`Metacrunch::Input` and `Metacrunch::Output`. Format readers and writers
(JSON Lines, MARCXML, later CSV and others) hold one of these objects and
keep only their format logic. A source or sink of one's own gets gzip, tar,
`"-"`, IOs, progress and pipe handling in a few lines.

The layer separates the container (file, gzip, tar) from the format, as
Embulk separates decoders from parsers and Metafacture puts `open-file` and
`open-tar` before `decode-xml`.

Rejected alternatives:

- **Base classes with template methods** (`FileReader#read_document`,
  `FileWriter#serialize` with `header`/`footer` hooks, like Catmandu's
  `Catmandu::Importer` role): fewest lines per format, but couples format and
  lifecycle by inheritance, the hooks must foresee every format, and a source
  with two inputs (data plus a lookup file) does not fit.
- **Module functions only** (`each_document(targets)`, `open_output(target)`
  returning `[io, own]`): the smallest API, but the state (progress, broken
  pipe, ownership) moves back into every reader and writer.
- **Detection by file name**, as JsonLines and 4.x did: `"-"` and IOs would
  stay raw, and a wrongly named file would fail in the format.
- **Decompressing bzip2, xz and zstd through external programs**: results
  would depend on what is installed, and child processes bring exit codes,
  Ctrl-C and fork workers into the layer.
- **Directories and glob patterns as targets**: the layer would need rules
  for recursion, order, hidden files and symlinks, and macOS puts
  `.DS_Store` files everywhere. `Dir.glob(...).sort` in the recipe states
  these choices explicitly.
- **Overwrite protection or atomic replacement of outputs**: the user's own
  4.x jobs turned the protection off every time; atomic replacement would
  need the run's outcome in `close` and is a topic of its own.
- **A source with one record per file** (the direct successor of
  `FileSource`): postponed until a real case appears.

### 1.1 Goals

- `Metacrunch::Input`: documents from paths, `"-"`, IOs and Arrays of them,
  with gzip and tar detected by content, nested, and a uniform stream per
  document.
- `Metacrunch::Output`: an output to a path (gzip by name), `"-"` or an IO,
  with pipe handling and ownership in one place.
- `Metacrunch::InputError` and `Metacrunch::OutputError` with messages that
  name the file, and the tar member where there is one.
- `JsonLines::Reader`, `JsonLines::Writer`, `Marcxml::Reader` and
  `Marcxml::Writer` built on the layer, without their own copies.
- The `source` and `sink` generator templates use the layer.
- `docs/files.md` for authors of sources and sinks.

### 1.2 Non-goals

- bzip2, xz, zstd, zip and 7z decoding; writing tar archives.
- Directories and glob patterns as targets.
- Overwrite protection, appending, atomic replacement.
- A source with one record per file (see 12).
- CSV and XLSX (a later sub-project, the successor of metacrunch-file).
- Several paths for `-i` on the command line.

### 1.3 Success criteria

- `metacrunch run job.rb -i dump.tar.gz` reads the JSON Lines of every
  member; `cat dump.jsonl.gz | metacrunch run job.rb -i -` reads gzip from
  stdin.
- `JsonLines::Reader.new(params.files)` reads an Array of files, each of
  them plain, gzip, tar or tar.gz, whatever its name.
- No gzip, tar, progress, pipe or ownership code is left in `json_lines.rb`
  and in the gem's `reader.rb` and `writer.rb`.
- All existing tests of JsonLines and Marcxml pass, with only the expected
  error classes changed (section 5).
- Every rule of sections 2 to 6 has a test.
- Reading JSON Lines is not slower than before, plain or gzip; writing is at
  most 5 % slower; `Marcxml::Reader` from a file stays within 5 % of its
  current 28.7 µs per record (section 10.3).
- Line and branch coverage stay above the thresholds of `test/test_helper.rb`;
  RuboCop finds no offense in core and in the gem.

### 1.4 Decisions

Approved by the user between 2026-10-23 and 2026-10-25:

- An IO layer in core; JsonLines and the marcxml gem build on it.
- Helper objects that readers and writers hold (approach 1), not base classes
  or module functions.
- Detection by content (magic bytes) for files, `"-"` and IOs alike; names do
  not matter on input.
- gzip and tar are decoded. bzip2, xz, zstd and zip are recognized and raise
  with a hint to decompress first.
- No directories and no globs; several files are given as an Array.
- Outputs are always overwritten; there is no option.
- The source with one record per file is postponed (option kept for later).
- Section 1 (units and API), 2 (detection and decoding, including skipping
  tar members whose name starts with a dot), 3 (progress, resources, input
  errors), 4 (output), 5 (migration of JsonLines, CLI, generators, Marcxml)
  and 6 (tests, performance, documentation) of the design, approved one by
  one on 2026-10-25.

Added while writing the spec, from checks on Ruby 4.0.7 and RubyGems 4.0.20:

- `Gem::Package::TarReader` truncates silently: an archive cut inside a
  member's data yields the shorter data, and one cut inside a header yields
  a member of 0 bytes, both without an error. The layer checks this itself
  (3.3). The marcxml gem has this data loss today.
- `Zlib::GzipReader#read` does not notice a gzip file that lacks only its
  footer; `finish` raises `Zlib::GzipFile::NoFooter`, and `readpartial`
  raises when the end is reached. The layer reads gzip by `readpartial`
  (3.2).
- `tar` on macOS writes AppleDouble members (`._name`) next to the real
  files, also for freshly created files. Skipping members whose base name
  starts with a dot (3.3) is therefore needed, not only a nicety.

Amended after the final review (2026-10-25):

- A tar archive is read to the end of its input after the end-of-archive
  marker, so that a gzip layer around it reaches and checks its CRC and
  length (3.3); before, a corrupt or cut `.tar.gz` passed.
- The checksum of a tar header is checked by the layer; RubyGems parses the
  field but never checks it. A member name with a NUL byte is broken (3.3).
- Members of type `7` (contiguous file) are regular files (3.3).
- Detection reads ahead block by block and decides as soon as the first
  bytes allow it; it no longer waits for 262 bytes of a slow pipe (3.1).
- `Stream#each_line` searches every block for `"\n"` once, so long lines
  cost linear time (2.2).

Amended with the review's minors (2026-10-25):

- Hints quote the path and name a file only for its outer layer (3.4).
- `Output#close` returns nil; errors of closing a file that is discarded
  after another error are dropped (6.3).
- The stream copies a non-binary block of an IO instead of changing its
  encoding (2.2).
- zlib's warning when a gzip member is ended early is dropped by a filter
  on `Warning.warn` for the finishing thread only; `$VERBOSE` stays as it
  is (3.2).
- `docs/files.md` names the known limits and the tar archive cut between
  two members.

## 2. Units and API

```ruby
Metacrunch::STDIO   # "-"

input = Metacrunch::Input.new(targets)
input.each_document { |stream, name| ... }   # without a block an Enumerator
input.progress                               # 0.0..1.0 or nil

output = Metacrunch::Output.new(target)
output.open
output.write(string)
output.close
```

`Metacrunch::STDIO` (`"-"`) replaces `JsonLines::STDIO` and the `STDIO`
constants of the gem's reader and writer.

### 2.1 `Input`

`Input.new(targets)` takes a target or a non-empty Array of targets. A target
is a String path, a Pathname, `"-"` (stdin) or an IO-like object, i.e. one
that responds to `readpartial` or `read`. Anything else, an empty String, an
empty Array and nested Arrays raise `ArgumentError`. `new` checks types only
and touches no file, so `--help`, `check` and tests with another source read
nothing.

`each_document` yields every document of the targets as a `Stream` and its
name (2.3), in order: the targets in the given order, the members of a tar
archive in archive order. A plain or gzip target is one document; a tar
archive is one document per regular member (section 3). Without a block it
returns an Enumerator. Every call reads path targets again from the start;
IOs, stdin included, are read from where they are, so a second call finds
them at their end. `"-"` means the `$stdin` of the moment `each_document`
is called.

`Input` has no `each`: it is a building block for sources, not a source, and
`source Metacrunch::Input.new(...)` fails at once instead of yielding pairs.

`progress` is described in 4.2.

An `Input` is used from one thread. Only `progress` may be read from another
thread (the progress display does so).

### 2.2 `Stream`

`Metacrunch::Input::Stream` is the one class of every document, whatever it
comes from (file, gzip, tar member, IO). Users do not create it.

| Method | Returns |
|---|---|
| `read(length = nil)` | without length the rest of the document (`""` at the end); with length up to that many bytes, `nil` at the end |
| `readpartial(length)` | 1 to `length` bytes; raises `EOFError` at the end |
| `each_line { \|line\| }` | every line including its `"\n"` (the last one may lack it); `"\r\n"` is kept; without a block an Enumerator |
| `peek(length)` | up to `length` bytes ahead without consuming them (`""` at the end) |
| `eof?` | true at the end of the document |

- Strings are binary (`Encoding::BINARY`) and new objects; the format sets
  the encoding (JsonLines forces UTF-8 per line).
- The stream reads its source in blocks of 64 KiB. Lines may span blocks;
  a line of any length is yielded whole.
- A stream is valid until the next document is yielded or the iteration
  ends; afterwards its methods raise `IOError` ("stream closed").

A spike on 1 million JSON Lines (97 MB) measured this splitting in Ruby
against the native `each_line`: plain file 53 vs 60 ms, gzip 106 vs 189 ms,
with `JSON.parse` 253 vs 263 ms. One class for all cases costs nothing.

### 2.3 Names

`name` labels a document in messages:

| Document | Name |
|---|---|
| a file | the path as given (a Pathname as its `to_s`): `data/a.jsonl.gz` |
| a tar member | the archive's name, `:` and the member's full name: `dump.tar.gz:records/0001.xml` |
| a member of a nested tar | `outer.tar:inner.tar:file.xml` |
| stdin | `-` |
| an IO | its `path` if it responds to `path` with a String, else its class name: `StringIO` |

A gzip layer does not change the name. Known limit: RubyGems' tar reader does
not apply pax `path` records, so a member name longer than the ustar fields
can appear shortened in the name; its data is read in full.

### 2.4 `Output`

`Output.new(target)` takes a String path, a Pathname, `"-"` (stdout) or an
IO-like object, i.e. one that responds to `write`. Anything else and an empty
String raise `ArgumentError`. `new` touches no file. `open`, `write` and
`close` are described in section 6. An `Output` is used from one thread.

### 2.5 Errors

```ruby
class InputError < Error; end    # a target could not be read
class OutputError < Error; end   # an output could not be opened or written
```

Both are `Metacrunch::Error`s. Messages start with the name (2.3) and a
colon; the original error, if any, is the `cause`. Section 5 lists them.

## 3. Detection and decoding

### 3.1 Rules

Before a document is yielded, the layer looks at up to 262 bytes. The check
runs on every layer: on every target, on the content of every gzip layer and
on every tar member. It reads ahead one block at a time and decides as soon
as it can: tar needs 262 bytes unless a `"\n"` in the first 100 bytes (the
name field of a tar header), before any NUL, rules it out. So a line-based
format on a slow pipe is not held back beyond its first line.

| Start | Format | Effect |
|---|---|---|
| `1F 8B 08` | gzip | decode all members (3.2), then check the content again |
| `ustar` at byte 257 | tar | every regular member (3.3) is checked again and becomes a document |
| `BZh` + `1`..`9` + `31 41 59 26 53 59` or `17 72 45 38 50 90` | bzip2 | `InputError` (3.4) |
| `FD 37 7A 58 5A 00` | xz | `InputError` (3.4) |
| `28 B5 2F FD` | zstd | `InputError` (3.4) |
| `50 4B 03 04` or `50 4B 05 06` | zip | `InputError` (3.4) |
| anything else | | the document as it is |

- `.tar.gz` and `.tgz` become tar through the gzip layer; a tar of `.gz`
  files works, since every member is checked again; `.gz.gz` is gzip twice.
- At most 4 layers of gzip and tar: a fifth raises `InputError` (5.1). A
  `.tar.gz` with `.gz` members needs 3. The limit stops gzip quines (files
  that decompress to themselves).
- An empty input, an empty gzip content and an empty member are each one
  empty document; the format yields no records for it.
- Input shorter than 262 bytes is never tar.
- Detection works on stdin and pipes too: the stream buffers what it peeks
  and never rewinds.
- Known limit: v7 tar archives without the `ustar` magic are read as plain
  content.

### 3.2 gzip

- The gzip layer reads by `readpartial`, so a truncated file always raises,
  also when only its footer is missing.
- After a member, the rest of the input is checked: nothing left ends the
  document; a gzip start begins the next member (as `zcat` reads files
  written with `cat a.gz b.gz` or `gzip >>`); anything else raises
  `InputError` ("data after the end of the gzip data"), also zero padding.
- A gzip layer is ended with `finish`, never `close`, so the input below
  stays open. When reading stops early (`break`, an error, `limit`), the
  unread rest is not checked and raises nothing.

### 3.3 tar

- Only regular files (type `0`, the NUL of older tars, and `7`) are
  documents. Directories, symbolic links, hard links, pax headers and GNU
  sparse files are skipped.
- Members whose base name starts with `.` are skipped: AppleDouble files
  (`._name`) that `tar` on macOS adds, and `.DS_Store`.
- The layer checks what RubyGems does not: tar input that ends inside a
  512-byte block, or before a member's data is complete, raises `InputError`
  ("broken tar archive (…)"). A member the format did not read to its end is
  drained to check this when its block returns; when reading stops early
  (`break`, an error), nothing is drained or checked. A missing
  end-of-archive marker (the two zero blocks) is accepted, as GNU tar
  accepts it. After the marker, the rest of the input is read and dropped,
  so that a gzip layer around the archive reaches and checks its footer.
- The header checksum is checked (the unsigned sum, or the signed one older
  tars wrote): RubyGems parses the field but does not check it. A wrong sum
  and a member name with a NUL byte raise `InputError` ("broken tar archive
  (wrong header checksum)"), as do errors of RubyGems' header parser
  (`Gem::Package::TarInvalidError`, e.g. garbage).

### 3.4 Unsupported formats

The message names the format and the tool that decompresses it:

```
dump.jsonl.zst: is zstd compressed, which metacrunch cannot read; decompress it first, e.g. zstd -dc dump.jsonl.zst | metacrunch run job.rb -i -
```

The tools in the hints: `bzip2 -dc`, `xz -dc`, `zstd -dc`, `unzip -p`. The
command names the file (quoted for the shell) only when the format is the
outer layer of a file. For stdin the hint is a pipe (`... | zstd -dc |
metacrunch run job.rb -i -`); for IOs and documents inside gzip or tar it is
only the tool (`e.g. with zstd -dc`), since a command on the outer file
would decompress the wrong layer. A tar member's name has the member
(`dump.tar:a.jsonl.bz2`).

## 4. Input: order, progress, resources

### 4.1 Checks before the first document

At the start of `each_document`, before the first document, every path
target is checked: it must exist, must not be a directory and must be
readable. FIFOs and character devices are allowed (e.g. `/dev/stdin`).
A typo in the third of three files raises before anything is read, not after
an hour with half of the output written. A file that disappears after the
check raises when it is reached.

### 4.2 Progress

- The total is the sum of the sizes of all targets if all of them are
  regular files, else there is no total (stdin, an IO, a FIFO or a device
  among them).
- The done count is the number of bytes read from those files, counted in
  the reading thread for every block (for gzip, compressed bytes). The
  display thread only reads the two Integers.
- `progress` is `nil` without a total and before the first
  `each_document`, at most `1.0`, `1.0` after the last document, and `1.0`
  for a total of 0.
- The layer reads at most 64 KiB ahead of the format, so the value is at
  most one block ahead of the records.
- A new call of `each_document` starts again at 0.

### 4.3 Resources

- Files are opened in binary mode when they are reached, one at a time, and
  closed after their last document, also on `break`, errors and `throw`.
- IOs from outside, `$stdin` included, are never closed.

## 5. Errors

### 5.1 Input

Raised by `each_document`; all are `InputError` with the document's name
first:

| Case | Message |
|---|---|
| missing file | `data/b.jsonl: no such file` |
| directory | `data: is a directory` |
| not readable | `data/b.jsonl: permission denied` |
| other system error while opening or reading | `data/b.jsonl: input/output error` (the system's message, lower case first) |
| broken or truncated gzip | `dump.jsonl.gz: broken gzip data (invalid compressed data -- format violated)` |
| data after the gzip data | `dump.jsonl.gz: data after the end of the gzip data` |
| broken tar | `dump.tar.gz:records/7.xml: broken tar archive (ends inside the member's data)` |
| unsupported format | 3.4 |
| too deeply nested | `dump.gz: more than 4 layers of gzip and tar` |

These are errors of the source, not failures of records: under any failure
policy they stop the job (exit status 1). Records yielded before are already
on their way. Messages use the system's text without Ruby's `@ rb_sysopen -
path` suffix; the original `Errno` or `Zlib` error is the `cause`.

Today the same cases log `ERROR Errno::ENOENT: No such file or directory @
rb_sysopen - missing.jsonl` and `ERROR Zlib::GzipFile::Error: not in gzip
format` (without a file name); afterwards they log
`ERROR Metacrunch::InputError: missing.jsonl: no such file`.

### 5.2 Output

All are `OutputError` with the output's name first (the path as given, `-`,
or the IO's name as in 2.3):

| Case | Message |
|---|---|
| directory missing (on `open`) | `out/x.jsonl: no such directory` |
| not writable | `out.jsonl: permission denied` |
| the path is a directory | `out: is a directory` |
| other system error while opening, writing or closing | `out.jsonl: no space left on device` |
| refused name (6.1) | 6.1 |
| `open` twice | `out.jsonl: already open` |

A closed pipe is no `OutputError`; see 6.2.

## 6. Output

### 6.1 `open`

- A path: the file is created or truncated (binary mode). A name that ends
  with `.gz` (in any case) is written with gzip; there is no content yet to
  detect.
- A name that ends with `.bz2`, `.xz`, `.zst`, `.zip`, `.tar`, `.tar.gz` or
  `.tgz` (in any case) raises before anything is created, since the content
  would not match the name:
  - `out.jsonl.zst: metacrunch cannot write zstd; write plain output and compress it, e.g. metacrunch run job.rb | zstd > out.jsonl.zst`
    (likewise `bzip2`, `xz`, `zip` with `zip -q out.zip -`)
  - `out.tar.gz: metacrunch cannot write tar archives`
- `"-"` is the `$stdout` of the moment `open` is called; it and IOs from
  outside are not owned by the output.

### 6.2 `write`

- Writes the String as it is.
- `Errno::EPIPE` (the reader of a pipe went away, e.g. `| head`) raises
  `SignalException("PIPE")` once, so the run ends as if by SIGPIPE.
  Afterwards every `write` and the final flush do nothing. This is today's
  behavior of both writers, now in one place.
- Other system errors raise `OutputError` (5.2).

### 6.3 `close`

- An owned file is closed; with gzip its trailer is written first.
- An IO that is not owned is only flushed (if it responds to `flush`).
- `Errno::EPIPE` while flushing or closing raises SIGPIPE as in 6.2, once.
- After a broken pipe an owned file is closed and its buffer discarded.
- `close` before `open` and a second `close` do nothing.

The checks of the CLI for `-o`, `--rejects`, `--failures` and `--stats` stay
as they are (existing directory, no file twice); they work on paths before
the run.

## 7. JsonLines and the CLI

### 7.1 `JsonLines::Reader`

- `JsonLines::Reader.new(targets)` takes what `Input.new` takes, so Arrays,
  tar and gzip by content (also on stdin) work.
- `each` reads `@input.each_document` and every stream's `each_line`, with
  today's rules per line: UTF-8 forced, a byte order mark removed, blank
  lines skipped, invalid JSON or invalid UTF-8 yielded as `InvalidRecord`.
  Without a block it returns an Enumerator.
- `progress` is the input's.
- Removed: `GzipMembers`, `PROGRESS_EVERY`, `with_input`, `STDIO`.

### 7.2 `JsonLines::Writer` and `ContextWriter`

- `Writer` holds an `Output`: `open(_context)` opens it, `write` and
  `write_batch` write the lines, `close` closes it. The refusal of values
  that are not JSON types is unchanged.
- Removed: `guard`, `discard`, `output`, the `@broken`/`@own` state.
- `ContextWriter` is unchanged; it inherits from `Writer`.

### 7.3 CLI

- `run_options.rb` and `cli/run.rb` use `Metacrunch::STDIO`.
- The help of `-i` reads `Read JSON Lines from PATH (- for stdin; gzip and
  tar are unpacked)`.
- `-i -` keeps passing the injected stdin IO, and `-o -`, `--rejects -` and
  `--failures -` the injected stdout IO, so tests of the CLI still run
  without the real stdin and stdout.

## 8. Generator templates

`generate source` and `generate sink` produce classes on the layer, so every
new source reads gzip, tar, `"-"` and Arrays and reports progress, and every
new sink handles `"-"`, `.gz` and closed pipes:

```ruby
# frozen_string_literal: true

require "metacrunch"

# A source: yields a record for each line of its targets (paths, "-" for
# stdin, IOs or an Array of them; gzip and tar are unpacked). The targets
# are read in each, not in new, so that --help, check and tests with
# another source read nothing. In a job:
#   source Catalog::Lines.new(params.input)
class Catalog::Lines

  def initialize(targets)
    @input = Metacrunch::Input.new(targets)
  end

  # Optional: called once before the first record, with context.params
  # and context.logger.
  # def open(context) = nil

  def each
    @input.each_document do |stream, _name|
      stream.each_line { |line| yield({"line" => line.chomp.force_encoding(Encoding::UTF_8)}) }
    end
  end

  # Optional: the share of the input read so far, for the progress display.
  def progress = @input.progress

  # Optional: called at the end, also after an error.
  # def close = nil

end
```

```ruby
# frozen_string_literal: true

require "json"
require "metacrunch"

# A sink: writes each record as a line of JSON to its target (a path, "-"
# for stdout or an IO; .gz is compressed). In a job:
#   sink Catalog::Lines.new(params.output)
class Catalog::Lines

  def initialize(target)
    @output = Metacrunch::Output.new(target)
  end

  # Called once before the first record.
  def open(_context) = @output.open

  def write(record)
    @output.write("#{::JSON.generate(record)}\n")
  end

  # Optional: with `sink Catalog::Lines.new(...), batch: 1000` the job calls
  # write_batch with up to 1000 records instead of write.
  # def write_batch(records) = records.each { write(it) }

  # Called at the end, also after an error.
  def close = @output.close

end
```

The class and constant names come from the generator as today; the code
above shows `Catalog::Lines`. Both templates gain `require "metacrunch"`,
since the generated tests of files given by path load the file without
metacrunch. The generated tests keep their cases (lines in, records out;
records in, lines out) and stay within the line limit.

## 9. metacrunch-marcxml

On a branch `metacrunch-ng-io` of the gem, from its `metacrunch-ng` at
ddb2e67.

### 9.1 `Reader`

- `Reader.new(targets, parse:, normalize:)` holds an `Input`; the type
  checks of targets are the input's (`ArgumentError` as today).
- `each` reads `@input.each_document`; every stream is checked for XML with
  `stream.peek(64)` (after a byte order mark and whitespace it must start
  with `<`, an empty document passes) and split with `Marcxml.each_xml`,
  which reads the stream by `readpartial`.
- The XML check now applies to every document (stdin, IOs, gzip content and
  tar members too), not only to regular files, and raises `InputError`
  (`dump.tar:a.json: is not XML: it starts with "{\"id\":1"`).
- `progress` is the input's.
- Removed: `with_input`, `each_document`, `head`, `gunzip`, `members`,
  `each_entry`, `GzipMembers`, `total_size`, `path?`, `check_target`, the
  progress arithmetic, `STDIO`, `GZIP_MAGIC`, `PROGRESS_EVERY`, about 100
  lines.

New behavior: tar is detected without a matching name; members whose name
starts with a dot are skipped; a truncated tar raises instead of losing
data silently; errors are `InputError`.

### 9.2 `Writer`

- `Writer` holds an `Output`: `open` opens it and writes the XML header and
  `<collection>`; `close` writes `</collection>` (if `open` succeeded) and
  closes the output, also after an aborted run, as today.
- Removed: `guard`, `discard`, `output`, `STDIO`, `GZIP`.

### 9.3 Order

The gem's CI checks out `ubpb/metacrunch` at `metacrunch-ng`. Its branch
can only pass in CI once the core part is merged into `metacrunch-ng` and
pushed, which the user does. Locally the gem runs against the core worktree
through `METACRUNCH_PATH`.

## 10. Tests and performance

### 10.1 Core unit tests

`test/unit/input_test.rb`, `test/unit/input_stream_test.rb` and
`test/unit/output_test.rb`. Test data is built in a temporary directory
with `Zlib` and `Gem::Package::TarWriter`; no binary fixtures. The
AppleDouble case uses a member named `._a.jsonl`.

- **Detection:** plain; gzip; gzip with several members; tar; tar.gz with
  and without a matching name; tar with `.gz` members; gzip inside gzip;
  five layers (error); each unsupported format by its magic bytes and its
  message; a file shorter than 262 bytes; an empty file, an empty gzip, an
  empty member.
- **tar members:** directories, symbolic links and dot members skipped; a
  member read only partly by the format; an archive cut inside a member's
  data and inside a header (errors); a bad checksum (error); a missing end
  marker (accepted).
- **gzip:** broken, truncated, truncated in the footer only, data after the
  end, zero padding (errors); stopping early raises nothing.
- **Targets:** String, Pathname, `"-"` (with `$stdin` replaced), an IO from
  outside (stays open), an IO with only `read`, an IO with only
  `readpartial`, Array order, invalid targets, an empty Array, a nested
  Array, no `each` method.
- **Checks before reading:** the third of three files missing yields
  nothing; a directory; a file without read permission (skipped when run as
  root); a FIFO (read, no progress).
- **Progress:** `nil` before reading; growing while reading; `1.0` at the
  end; across files; the compressed position for gzip; a total of 0; `nil`
  with stdin in an Array; read from another thread while reading.
- **Resources:** files closed on `break`, on an error in the block and on
  `throw`; streams raise `IOError` after their block.
- **Names:** in every message of 5.1, including nested members.
- **Stream:** `read` with and without length, `readpartial` and `EOFError`,
  `peek` past the end, `eof?`; `each_line` with `"\r\n"`, a line longer than
  64 KiB, a last line without `"\n"`, empty lines; binary encoding.
- **Output:** a path, a Pathname, gzip round trip, `.GZ`, every refused name
  (nothing created), `"-"` and an IO from outside (flushed, not closed), a
  closed pipe raises SIGPIPE once and nothing afterwards, a pipe closed
  before the final flush, `close` before `open` and twice, `open` twice,
  errors on `open` (directory missing, path is a directory, no permission)
  and on `write` (`Errno::ENOSPC` from a stub IO).

### 10.2 Existing and integration tests

- JsonLines: all tests stay; the expected error classes change to
  `InputError`. New: Arrays, tar, gzip without `.gz`, gzip on stdin,
  `each` without a block.
- CLI: an integration test of `metacrunch run job.rb -i dump.tar.gz` and of
  gzip piped to `-i -`; a missing `-i` file prints the new message and ends
  with exit status 1.
- Generators: the generated tests of the new templates pass (by name and by
  path), and RuboCop finds no offense in the generated files, as the
  existing end-to-end test checks.
- Marcxml: all tests stay, with `InputError` where `Errno::ENOENT`,
  `Zlib::GzipFile::Error` or the "not XML" `Metacrunch::Error` were
  expected. New: tar without a matching name, dot members skipped, a
  truncated tar raises, the XML check on stdin.

### 10.3 Performance

A script `bench/io.rb` next to `bench/executor.rb` builds 1 million JSON
Lines (plain and gzip) in a temporary directory and measures
`JsonLines::Reader` and `JsonLines::Writer`. Run on c7ae107 and on the new
code:

- reading plain and gzip: not slower;
- writing: at most 5 % slower;
- `Marcxml::Reader` from a file: within 5 % of 28.7 µs per record (measured
  with the gem's test data, as for the gem's spec).

The numbers go into the commit message.

## 11. Documentation

- `docs/files.md` (new): what `Input` and `Output` accept, detection and
  decoding, names, errors, progress, and how to build a source or a sink on
  them (the code of section 8).
- `docs/jobs.md`: Sources and Sinks describe `JsonLines::Reader` with
  Arrays, gzip and tar by content, and point to `docs/files.md`.
- Readme: the paragraph on extension gems and the list of documentation
  point to `docs/files.md`; `-i` examples mention gzip and tar where they
  read files.
- `docs/cli.md`: the help text of `-i`.
- CHANGELOG under 5.0.0: added `Metacrunch::Input`, `Metacrunch::Output`,
  `Metacrunch::STDIO`, `InputError`, `OutputError`; `JsonLines::Reader`
  reads Arrays and tar; changed: gzip is detected by content, input errors
  are `InputError` instead of `Errno` and `Zlib` errors.
- metacrunch-marcxml Readme: reading points to metacrunch's `docs/files.md`
  for gzip, tar and errors; the gem's CHANGELOG notes the new behavior of
  9.1.

## 12. Deferred

- A source with one record per file or member, e.g.
  `{"path" => ..., "member" => ..., "content" => ...}` (open: encoding, size
  limit, memory).
- CSV and XLSX in a gem (the successor of metacrunch-file).
- bzip2, xz, zstd and zip decoding; writing tar.
- Several paths for `-i`.
- Overwrite protection and atomic replacement of outputs.
