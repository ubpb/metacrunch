# The IO layer: Metacrunch::Input and Metacrunch::Output — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One public layer in core that opens what sources read and sinks write — gzip and tar detected by content, several targets, progress, closed pipes, ownership of IOs — with JsonLines, the generator templates and metacrunch-marcxml built on it.

**Architecture:** `Metacrunch::Input#each_document` yields one `Input::Stream` per document. A stream reads its source (`Raw` for files and IOs, `Gzip` for the content of gzip data, `Tar::Member` for a tar member) in 64 KiB blocks and offers `read`, `readpartial`, `each_line`, `peek` and `eof?`. Detection (`Input::Formats`) runs on every layer and recurses up to 4 layers. `Metacrunch::Output` owns opening (gzip by name), writing (EPIPE → SIGPIPE once) and closing. Format readers and writers hold one of these objects.

**Tech Stack:** Ruby 4.0 (`zlib`, `rubygems/package` only), Minitest, RuboCop (rubocop-ubpb), SimpleCov.

**Spec:** `docs/superpowers/specs/2026-10-25-metacrunch-ng-io-layer-design.md`

## Global Constraints

- Ruby 4.0; no new runtime dependency (only `logger`); the layer uses `zlib` and `rubygems/package` from Ruby.
- metacrunch 5 is unreleased: `JsonLines::STDIO` and the gem's `STDIO`, `GZIP`, `GZIP_MAGIC`, `PROGRESS_EVERY` constants are removed without aliases.
- Repository docs, comments and commit messages in English; examples generic (no internal or institution names) in `Readme.md`, `docs/` and `examples/`.
- `bundle exec rake` passes in core and, from Task 9 on, in the gem: tests, coverage at least 95 % lines and 90 % branches, RuboCop with no offenses.
- Tests run with `-w` (Minitest::TestTask): nothing may print warnings. zlib warns when a gzip member is ended in the middle; `Input::Gzip#finish` silences it.
- Every commit ends with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Unchanged: the engine, executors, `RunOptions` checks (existing directory, no file twice), the JSON of `ContextWriter`, `InvalidRecord` rules of `JsonLines::Reader`, the exit codes.
- Core work happens in the worktree `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch/.claude/worktrees/metacrunch-ng-io` (branch `metacrunch-ng-io`); gem work in `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-marcxml/.claude/worktrees/metacrunch-ng-io` (branch `metacrunch-ng-io` from the gem's `metacrunch-ng`, ddb2e67), created in Task 9.

## Review Focus

1. A line that spans two gzip members (`cat a.gz b.gz` where `a` ends without `"\n"`): read as one line, as `zcat` prints it. Test in Task 3 (`test_a_line_may_span_two_gzip_members`).
2. Breaking out inside a gzip member that sits in a tar.gz (a nested layer stopped early): the file is closed and nothing is printed under `-w`. Test in Task 4 (`test_breaking_out_of_a_nested_member_closes_the_file_quietly`).
3. A FIFO together with a regular file in one Array: both are read in order, and progress stays `nil`. Test in Task 2 (`test_a_fifo_in_an_array_is_read_without_progress`).
4. A source IO that returns frozen or UTF-8 Strings from `readpartial`: the stream neither raises `FrozenError` nor hands out non-binary Strings. Test in Task 1 (`test_frozen_and_utf8_blocks_from_the_source`).
5. Empty input on the command line, both empty stdin and an empty gzip file with `-i`: zero records, exit status 0. Test in Task 6 (`test_empty_input_gives_no_records`).

## Amendments to the spec made while planning

- `Output#write` before `open` (or after `close`) raises `IOError` ("NAME: not open"); the spec did not say.
- An unsupported format read from stdin or an IO names `FILE` in its hint (`zstd -dc FILE | metacrunch run job.rb -i -`), since there is no file name.
- An IO named `$stdin` or `$stdout` gets the name `-`; an IO of an anonymous class gets the name of its first named ancestor (`StringIO`).
- The tests of Input are split into `input_test.rb` (targets, checks, progress, resources), `input_decoding_test.rb` (detection, gzip) and `input_tar_test.rb` (tar), next to `input_stream_test.rb` and `output_test.rb`.
- CHANGELOG: 5.0.0 is unreleased and had no IO layer before, so the new behavior goes under "Added" only, not under a "Changed" entry.
- The help of `-i` keeps "instead of the job's source" and gains a second line "(gzip and tar are unpacked)", in `run` and `trace`.

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `lib/metacrunch/input/stream.rb` | Buffered binary reading of one document | 1 |
| `lib/metacrunch/files.rb` | `Metacrunch::STDIO`; `Files.path?`, `.name`, `.reason` | 2 |
| `lib/metacrunch/errors.rb` | `InputError`, `OutputError` | 2 |
| `lib/metacrunch/input.rb` | Targets, checks, progress, resources, layers | 2, 3, 4 |
| `lib/metacrunch/input/raw.rb` | Bytes of a file or IO, counted for progress | 2 |
| `lib/metacrunch/input/formats.rb` | Detection by magic bytes; unsupported formats | 3, 4 |
| `lib/metacrunch/input/gzip.rb` | All members of gzip data | 3 |
| `lib/metacrunch/input/tar.rb` | Regular members of a tar archive, with truncation checks | 4 |
| `lib/metacrunch/output.rb` | Opening, writing, closing an output | 5 |
| `lib/metacrunch.rb` | Requires | 2, 5 |
| `lib/metacrunch/json_lines.rb` | Reader on `Input`, writers on `Output` | 6 |
| `lib/metacrunch/run_options.rb`, `lib/metacrunch/cli/run.rb`, `lib/metacrunch/cli/trace.rb` | `STDIO`; help of `-i` | 6 |
| `bench/io.rb` | Reading and writing JSON Lines through the layer | 6 |
| `lib/metacrunch/templates/source/file.rb.erb`, `lib/metacrunch/templates/sink/file.rb.erb` | Templates on the layer | 7 |
| `docs/files.md` (new), `docs/jobs.md`, `docs/cli.md`, `docs/workers.md`, `Readme.md`, `CHANGELOG.md` | Documentation | 8 |
| gem `lib/metacrunch/marcxml/reader.rb`, `bench/parse.rb` | Reader on `Input` | 9 |
| gem `lib/metacrunch/marcxml/writer.rb`, `Readme.md`, `CHANGELOG.md` | Writer on `Output`; docs | 10 |

Task order: 1 → 2 → … → 10. Each task leaves `bundle exec rake` green in its repository.

How to run one test file in core (from the core worktree):

```bash
bundle exec ruby -Itest -Ilib test/unit/input_stream_test.rb
```

---

### Task 1: `Input::Stream`

**Files:**
- Create: `lib/metacrunch/input/stream.rb`
- Test: `test/unit/input_stream_test.rb`

**Interfaces:**
- Produces: `Metacrunch::Input::Stream.new(source)` where `source.readpartial(length)` returns up to `length` bytes and raises `EOFError` at the end. Public: `read(length = nil)`, `readpartial(length, outbuf = nil)`, `each_line(&)`, `peek(length)`, `eof?`. Internal (used by later tasks): `unread(bytes)` (Task 3), `close` (Task 2). Constant `Stream::BLOCK = 65_536` (Task 4 drains members in blocks of this size).
- `lib/metacrunch.rb` does not require it yet (Task 2 does, through `input.rb`); the test requires it directly.

- [ ] **Step 1: Write the failing test**

Create `test/unit/input_stream_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/input/stream"

class InputStreamTest < Minitest::Test

  Stream = Metacrunch::Input::Stream

  # A source that hands out the given blocks one per readpartial and
  # records the lengths asked for.
  class Blocks

    attr_reader :lengths

    def initialize(*blocks)
      @blocks = blocks
      @lengths = []
    end

    def readpartial(length)
      @lengths << length
      @blocks.shift || raise(EOFError, "end")
    end

  end

  def stream(*blocks) = Stream.new(Blocks.new(*blocks.map(&:b)))

  def test_read_without_length_reads_the_rest
    stream = stream("ab", "cd")

    assert_equal "abcd", stream.read
    assert_equal "", stream.read
  end

  def test_read_with_length_reads_up_to_it_and_nil_at_the_end
    stream = stream("abc", "de")

    assert_equal "", stream.read(0)
    assert_equal "abcd", stream.read(4)
    assert_equal "e", stream.read(4)
    assert_nil stream.read(1)
  end

  def test_readpartial_reads_up_to_length_and_raises_at_the_end
    stream = stream("abc")
    buffer = +"old"

    assert_equal "ab", stream.readpartial(2)
    assert_same buffer, stream.readpartial(10, buffer)
    assert_equal "c", buffer
    assert_raises(EOFError) { stream.readpartial(1) }
  end

  def test_peek_does_not_consume
    stream = stream("ab", "cd")

    assert_equal "abc", stream.peek(3)
    assert_equal "abcd", stream.peek(10)
    assert_equal "abcd", stream.read
    assert_equal "", stream.peek(1)
  end

  def test_eof
    stream = stream("a")

    refute_predicate stream, :eof?
    stream.read(1)

    assert_predicate stream, :eof?
  end

  def test_each_line_keeps_line_ends_and_the_last_line_without_one
    lines = stream("a\r\nb\n", "\n", "\nlast").each_line.to_a

    assert_equal ["a\r\n", "b\n", "\n", "\n", "last"], lines
  end

  def test_lines_span_blocks_and_may_be_longer_than_a_block
    long = "x" * (Stream::BLOCK + 10)
    lines = stream("1\n2", "3\n#{long[0, 100]}", long[100..], "\n4").each_line.to_a

    assert_equal ["1\n", "23\n", "#{long}\n", "4"], lines
  end

  def test_each_line_without_a_block_is_an_enumerator
    assert_instance_of Enumerator, stream("a\n").each_line
  end

  def test_an_empty_source_has_no_lines
    assert_empty stream.each_line.to_a
    assert_predicate stream, :eof?
  end

  def test_frozen_and_utf8_blocks_from_the_source
    source = Blocks.new("ä\n".freeze, "ö\n".encode(Encoding::UTF_8).freeze)
    lines = Stream.new(source).each_line.to_a

    assert_equal ["ä\n".b, "ö\n".b], lines
    assert(lines.all? { it.encoding == Encoding::BINARY && !it.frozen? })
  end

  def test_reads_the_source_in_blocks
    source = Blocks.new("a")
    Stream.new(source).read

    assert_equal [Stream::BLOCK, Stream::BLOCK], source.lengths
  end

  def test_unread_puts_bytes_in_front
    stream = stream("cd")
    stream.unread("ab")

    assert_equal "abcd", stream.read
  end

  def test_a_closed_stream_raises
    stream = stream("a")
    stream.close

    [-> { stream.read }, -> { stream.readpartial(1) }, -> { stream.each_line { nil } }, -> { stream.peek(1) },
     -> { stream.eof? }].each do |call|
      assert_equal "stream closed", assert_raises(IOError, &call).message
    end
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/input_stream_test.rb`
Expected: `LoadError` (cannot load such file -- metacrunch/input/stream).

- [ ] **Step 3: Implement**

Create `lib/metacrunch/input/stream.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Input
    # The bytes of one document: a file, the content of a gzip layer, a tar
    # member or an IO. Reads its source in blocks of BLOCK bytes through the
    # source's readpartial; all Strings it returns are binary and new. Valid
    # until the next document is yielded or the iteration ends.
    class Stream

      BLOCK = 65_536
      NEWLINE = "\n".b

      # source: an object whose readpartial(length) returns up to length
      # bytes and raises EOFError at the end.
      def initialize(source)
        @source = source
        @buffer = "".b
        @eof = false
        @closed = false
      end

      # Up to length bytes, nil at the end; without length the rest ("" at
      # the end).
      def read(length = nil)
        check_open
        return take(fill_all) if length.nil?
        return "".b if length.zero?

        fill(length)
        @buffer.empty? ? nil : take([length, @buffer.bytesize].min)
      end

      # 1 to length bytes; raises EOFError at the end. With outbuf, its
      # content is replaced and outbuf returned.
      def readpartial(length, outbuf = nil)
        check_open
        fill(1)
        raise EOFError, "end of document reached" if @buffer.empty?

        data = take([length, @buffer.bytesize].min)
        outbuf ? outbuf.replace(data) : data
      end

      # Yields every line with its "\n"; the last one may lack it. Without
      # a block an Enumerator.
      def each_line(&)
        return enum_for(:each_line) unless block_given?

        check_open
        loop do
          fill(1)
          break if @buffer.empty?

          last = @buffer.rindex(NEWLINE)
          if last
            take(last + 1).each_line(&)
          elsif @eof
            yield take(@buffer.bytesize)
          else
            @buffer << next_block
          end
        end
        nil
      end

      # Up to length bytes ahead, without consuming them ("" at the end).
      def peek(length)
        check_open
        fill(length)
        @buffer.byteslice(0, length)
      end

      def eof?
        check_open
        fill(1)
        @buffer.empty?
      end

      # Internal: puts bytes back in front of the buffer (the rest that a
      # gzip member did not use).
      def unread(bytes)
        @buffer = bytes.b + @buffer
      end

      # Internal: ends the stream for its reader.
      def close
        @closed = true
      end

      private

      def check_open
        raise IOError, "stream closed" if @closed
      end

      # Reads blocks until the buffer holds length bytes or the source ends.
      def fill(length)
        @buffer << next_block while @buffer.bytesize < length && !@eof
      end

      def fill_all
        @buffer << next_block until @eof
        @buffer.bytesize
      end

      # The next block as a binary String, or "" at the end (and @eof set).
      def next_block
        block = @source.readpartial(BLOCK)
        return block if block.encoding == Encoding::BINARY

        block.frozen? ? block.b : block.force_encoding(Encoding::BINARY)
      rescue EOFError
        @eof = true
        "".b
      end

      def take(length)
        data = @buffer.byteslice(0, length)
        @buffer = @buffer.byteslice(length, @buffer.bytesize - length)
        data
      end

    end
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -Itest -Ilib test/unit/input_stream_test.rb`
Expected: 13 runs, 0 failures, no warnings.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop lib/metacrunch/input/stream.rb test/unit/input_stream_test.rb
git add lib/metacrunch/input/stream.rb test/unit/input_stream_test.rb
git commit -m "Add Input::Stream, the buffered bytes of one document

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `Input` for plain documents

**Files:**
- Create: `lib/metacrunch/files.rb`, `lib/metacrunch/input.rb`, `lib/metacrunch/input/raw.rb`
- Modify: `lib/metacrunch/errors.rb` (after `class ProjectError < Error; end`), `lib/metacrunch.rb` (requires)
- Test: `test/unit/input_test.rb`, `test/unit/files_test.rb`, `test/unit/errors_test.rb`

**Interfaces:**
- Consumes: `Input::Stream` (Task 1).
- Produces: `Metacrunch::STDIO = "-"`. `Metacrunch::InputError < Error`, `Metacrunch::OutputError < Error`. `Metacrunch::Files.path?(target)`, `.name(target)`, `.reason(system_call_error)`. `Metacrunch::Input.new(targets)`, `#each_document { |stream, name| }` (Enumerator without block), `#progress`. Private `Input#layers(stream, name, file, depth, &)` is the hook Tasks 3 and 4 extend; `file` is what a hint names (the path, a member's full name, or nil). `Input::Raw.new(io, name, count: nil)` with `readpartial(length)`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/files_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class FilesTest < Minitest::Test

  Files = Metacrunch::Files

  def test_paths
    assert Files.path?("a.jsonl")
    assert Files.path?(Pathname("a.jsonl"))
    refute Files.path?("-")
    refute Files.path?(StringIO.new)
  end

  def test_names
    File.open(__FILE__) { assert_equal __FILE__, Files.name(it) }

    assert_equal "a/b.jsonl", Files.name(Pathname("a/b.jsonl"))
    assert_equal "-", Files.name("-")
    assert_equal "-", Files.name($stdin)
    assert_equal "-", Files.name($stdout)
    assert_equal "StringIO", Files.name(StringIO.new)
    assert_equal "StringIO", Files.name(Class.new(StringIO).new)
  end

  def test_reasons_are_the_system_text_in_lower_case
    assert_equal "no such file or directory", Files.reason(Errno::ENOENT.new("a.jsonl"))
    assert_equal "no space left on device", Files.reason(Errno::ENOSPC.new)
    assert_match(/\Aunknown error/, Files.reason(SystemCallError.new("x", 99_999)))
  end

end
```

Add to `test/unit/errors_test.rb` (inside the class):

```ruby
  def test_input_and_output_errors_are_metacrunch_errors
    assert_operator Metacrunch::InputError, :<, Metacrunch::Error
    assert_operator Metacrunch::OutputError, :<, Metacrunch::Error
  end
```

Create `test/unit/input_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class InputTest < Minitest::Test

  Input = Metacrunch::Input

  # An IO that can only read, as some wrappers do.
  class ReadOnly

    def initialize(content)
      @io = StringIO.new(content)
    end

    def read(length = nil) = @io.read(length)

  end

  # An IO that only has readpartial.
  class PartialOnly

    def initialize(content)
      @io = StringIO.new(content)
    end

    def readpartial(length) = @io.readpartial(length)

  end

  # A device that fails while reading.
  class Failing

    def readpartial(_length) = raise(Errno::EIO)

  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.chmod_R(0o755, @dir)
    FileUtils.remove_entry(@dir)
  end

  def test_reads_paths_pathnames_and_arrays_in_order
    first = write("a.jsonl", "1\n")
    second = write("b.jsonl", "2\n")

    assert_equal [[first, "1\n"], [second, "2\n"]], documents([first, Pathname(second)])
  end

  def test_dash_reads_stdin
    original = $stdin
    $stdin = StringIO.new("in\n")

    assert_equal [["-", "in\n"]], documents("-")
  ensure
    $stdin = original
  end

  def test_reads_ios_from_where_they_are_and_leaves_them_open
    io = StringIO.new("abc")
    io.read(1)
    input = Input.new(io)

    assert_equal [["StringIO", "bc"]], documents(input)
    assert_equal [["StringIO", ""]], documents(input)
    refute_predicate io, :closed?
  end

  def test_ios_with_only_read_or_only_readpartial
    assert_equal [["InputTest::ReadOnly", "r"]], documents(ReadOnly.new("r"))
    assert_equal [["InputTest::PartialOnly", "p"]], documents(PartialOnly.new("p"))
  end

  def test_files_given_as_ios_are_named_by_their_path
    path = write("a.jsonl", "1\n")

    File.open(path) { assert_equal [[path, "1\n"]], documents(it) }
  end

  def test_invalid_targets
    [42, nil, "", [["a.jsonl"]], [1]].each do |target|
      error = assert_raises(ArgumentError) { Input.new(target) }

      assert_match(/\Aa target must be a path, "-" or an IO, got /, error.message)
    end
    assert_equal "targets must not be empty", assert_raises(ArgumentError) { Input.new([]) }.message
  end

  def test_new_touches_no_file_and_input_is_no_source
    input = Input.new(File.join(@dir, "missing.jsonl"))

    refute_respond_to input, :each
    assert_nil input.progress
  end

  def test_all_paths_are_checked_before_the_first_document
    missing = File.join(@dir, "missing.jsonl")
    seen = []
    error = assert_raises(Metacrunch::InputError) do
      Input.new([write("a.jsonl", "1"), write("b.jsonl", "2"), missing]).each_document { seen << it }
    end

    assert_empty seen
    assert_equal "#{missing}: no such file", error.message
  end

  def test_a_directory_is_no_target
    error = assert_raises(Metacrunch::InputError) { documents(@dir) }

    assert_equal "#{@dir}: is a directory", error.message
  end

  def test_an_unreadable_file
    skip "root reads every file" if Process.uid.zero?
    path = write("secret.jsonl", "1\n")
    File.chmod(0o000, path)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}: permission denied", error.message
  end

  def test_errors_while_reading_name_the_target
    error = assert_raises(Metacrunch::InputError) { documents(Failing.new) }

    assert_equal "InputTest::Failing: input/output error", error.message
    assert_instance_of Errno::EIO, error.cause
  end

  def test_a_fifo_in_an_array_is_read_without_progress
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    writer = Thread.new { File.write(fifo, "from the fifo\n") }
    input = Input.new([fifo, write("a.jsonl", "1\n")])

    assert_equal ["from the fifo\n", "1\n"], documents(input).map(&:last)
    assert_nil input.progress
  ensure
    writer&.join
  end

  def test_progress_from_before_to_after_reading
    input = Input.new([write("big.jsonl", "x" * (3 * Metacrunch::Input::Stream::BLOCK)), write("small.jsonl", "y")])
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert_in_delta 1.0, input.progress
    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
  end

  def test_progress_starts_again_with_every_call
    path = write("big.jsonl", "x" * (3 * Metacrunch::Input::Stream::BLOCK))
    input = Input.new(path)
    documents(input)
    first = nil
    input.each_document { |stream, _name| first ||= stream.read(1) && input.progress }

    assert_operator first, :<, 1.0
  end

  def test_progress_of_empty_files_and_without_a_total
    empty = Input.new(write("empty.jsonl", ""))
    documents(empty)
    with_stdin = Input.new([write("a.jsonl", "1"), StringIO.new("2")])
    documents(with_stdin)

    assert_in_delta 1.0, empty.progress
    assert_nil with_stdin.progress
  end

  def test_progress_can_be_read_from_another_thread
    input = Input.new(write("big.jsonl", "x\n" * 200_000))
    values = Queue.new
    reader = Thread.new { 200.times { values << input.progress } }
    input.each_document { |stream, _name| stream.each_line { nil } }
    reader.join
    seen = Array.new(values.size) { values.pop }.compact

    assert_equal seen, seen.sort
  end

  def test_files_are_closed_on_break_errors_and_throw
    path = write("a.jsonl", "1\n2\n")
    Input.new(path).each_document { break }
    assert_raises(RuntimeError) { Input.new(path).each_document { raise "stop" } }
    catch(:done) { Input.new(path).each_document { throw :done } }

    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  def test_a_stream_is_closed_after_its_document
    kept = nil
    Input.new(StringIO.new("abc")).each_document { |stream, _name| kept = stream }

    assert_raises(IOError) { kept.read }
  end

  def test_each_document_without_a_block_is_an_enumerator
    path = write("a.jsonl", "1\n")

    assert_equal [[path, "1\n"]], Input.new(path).each_document.map { |stream, name| [name, stream.read] }
  end

  private

  def documents(input)
    input = Input.new(input) unless input.is_a?(Input)
    result = []
    input.each_document { |stream, name| result << [name, stream.read] }
    result
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/files_test.rb test/unit/errors_test.rb test/unit/input_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Files` (and `Metacrunch::InputError`, `Metacrunch::Input`).

- [ ] **Step 3: Implement**

Add to `lib/metacrunch/errors.rb` after `class ProjectError < Error; end`:

```ruby

  # A target could not be read: it is missing, a directory, not readable,
  # broken gzip or tar data, a format metacrunch cannot read, or nested too
  # deeply. The message starts with the name of the file or tar member.
  class InputError < Error; end

  # An output could not be opened, written or closed. The message starts
  # with the name of the output.
  class OutputError < Error; end
```

Create `lib/metacrunch/files.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  # "-" as a target: stdin for Input, stdout for Output.
  STDIO = "-"

  # What Input and Output share. Internal.
  module Files

    module_function

    def path?(target) = (target.is_a?(String) && target != STDIO) || target.is_a?(Pathname)

    # The name of a target in messages: a path as given, "-" for stdin and
    # stdout, an IO's path, or else the name of its class.
    def name(target)
      return target.to_s if path?(target) || target == STDIO
      return STDIO if target.equal?($stdin) || target.equal?($stdout)

      path = target.path if target.respond_to?(:path)
      path.is_a?(String) ? path : target.class.ancestors.find(&:name).name
    end

    # The system's text of a system error, lower case first, without
    # Ruby's " @ rb_sysopen - path".
    def reason(error)
      text = error.instance_of?(SystemCallError) ? error.message : error.class.new.message
      text.sub(/\A[A-Z]/, &:downcase)
    end

  end

end
```

Create `lib/metacrunch/input/raw.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Input
    # The bytes of a file or an IO, as the source of a Stream. Counts them
    # for progress if count is given. Internal.
    class Raw

      # io: responds to readpartial or read. count: called with the size of
      # every block, or nil.
      def initialize(io, name, count: nil)
        @io = io
        @name = name
        @count = count
        @partial = io.respond_to?(:readpartial)
      end

      def readpartial(length)
        block = @partial ? @io.readpartial(length) : read(length)
        @count&.call(block.bytesize)
        block
      rescue SystemCallError => e
        raise InputError, "#{@name}: #{Files.reason(e)}"
      end

      private

      def read(length)
        block = @io.read(length)
        raise EOFError, "end of file reached" if block.nil? || block.empty?

        block
      end

    end
  end
end
```

Create `lib/metacrunch/input.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # The documents of one or more targets, for sources and other readers.
  # Not a source itself: it has each_document, not each. Used from one
  # thread; only #progress may be read from another one. See docs/files.md.
  class Input

    # targets: a path (String or Pathname), "-" for stdin, an IO (anything
    # with readpartial or read), or a non-empty Array of these. Checks types
    # only and touches no file.
    def initialize(targets)
      list = targets.is_a?(Array) ? targets : [targets]
      raise ArgumentError, "targets must not be empty" if list.empty?

      @targets = list.map { target(it) }.freeze
      @total = nil
      @done = 0
    end

    # Yields a Stream and its name for every document. Checks all paths
    # before the first document. Without a block an Enumerator.
    def each_document(&)
      return enum_for(:each_document) unless block_given?

      @done = 0
      @total = total(check_paths)
      @targets.each { read_target(it, &) }
      @done = @total if @total
      nil
    end

    # The share of the files read so far, from 0.0 to 1.0 (compressed bytes
    # for gzip); nil before reading and unless all targets are regular
    # files.
    def progress
      total = @total
      return unless total
      return 1.0 if total.zero?

      [@done.fdiv(total), 1.0].min
    end

    private

    def target(target)
      return target.to_s if target.is_a?(Pathname)
      return target if target.is_a?(String) ? !target.empty? : io?(target)

      raise ArgumentError, "a target must be a path, \"-\" or an IO, got #{target.inspect}"
    end

    def io?(target) = target.respond_to?(:readpartial) || target.respond_to?(:read)

    # The File::Stat of every path; raises InputError for missing files,
    # directories and unreadable files.
    def check_paths
      @targets.filter_map do |target|
        next unless Files.path?(target)

        stat = File.stat(target)
        raise InputError, "#{target}: is a directory" if stat.directory?
        raise InputError, "#{target}: permission denied" unless File.readable?(target)

        stat
      rescue Errno::ENOENT
        raise InputError, "#{target}: no such file"
      rescue SystemCallError => e
        raise InputError, "#{target}: #{Files.reason(e)}"
      end
    end

    def total(stats)
      return unless stats.size == @targets.size && stats.all?(&:file?)

      stats.sum(&:size)
    end

    def read_target(target, &)
      return read_file(target, &) if Files.path?(target)

      io = target == STDIO ? $stdin : target
      name = Files.name(target)
      layers(Stream.new(Raw.new(io, name)), name, nil, 0, &)
    end

    def read_file(path, &)
      file = open_file(path)
      begin
        count = ->(bytes) { @done += bytes } if @total
        layers(Stream.new(Raw.new(file, path, count:)), path, path, 0, &)
      ensure
        file.close
      end
    end

    def open_file(path)
      File.open(path, "rb")
    rescue Errno::ENOENT
      raise InputError, "#{path}: no such file"
    rescue SystemCallError => e
      raise InputError, "#{path}: #{Files.reason(e)}"
    end

    # Yields the documents of stream. file: what the hint of an unsupported
    # format names (the path, a member's name, or nil); depth: the layers
    # of gzip and tar around stream. Tasks 3 and 4 add the detection.
    def layers(stream, name, _file, _depth, &) = document(stream, name, &)

    def document(stream, name)
      yield stream, name
    ensure
      stream.close
    end

  end
end

require_relative "input/stream"
require_relative "input/raw"
```

In `lib/metacrunch.rb`, before `require_relative "metacrunch/json_lines"`:

```ruby
require_relative "metacrunch/files"
require_relative "metacrunch/input"
```

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/files_test.rb test/unit/errors_test.rb test/unit/input_test.rb test/unit/input_stream_test.rb`
Expected: all pass, no warnings. Then `bundle exec rake` (everything green).

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/files.rb lib/metacrunch/errors.rb lib/metacrunch/input.rb lib/metacrunch/input/raw.rb \
  lib/metacrunch.rb test/unit/files_test.rb test/unit/errors_test.rb test/unit/input_test.rb
git commit -m "Add Metacrunch::Input for paths, stdin, IOs and Arrays of them

All paths are checked before the first document; progress counts the
bytes read from regular files in the reading thread.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Detection, gzip and unsupported formats

**Files:**
- Create: `lib/metacrunch/input/formats.rb`, `lib/metacrunch/input/gzip.rb`
- Modify: `lib/metacrunch/input.rb` (`MAX_LAYERS`, `layers`, `gzip`, `deeper`, class comment, requires)
- Test: `test/unit/input_decoding_test.rb`

**Interfaces:**
- Consumes: `Input#layers` hook, `Stream#unread`, `Stream#peek` (Tasks 1, 2).
- Produces: `Input::Formats::PEEK = 262`, `Formats::GZIP = "\x1F\x8B\x08".b`, `Formats.detect(head)` → `:gzip`, `:plain` or an `Formats::Unsupported` (`#message(name, file)`). Task 4 adds `:tar`. `Input::Gzip.new(stream, name)` with `readpartial(length)` and `finish`. `Input::MAX_LAYERS = 4`; private `Input#deeper(name, depth)` raises past it (Task 4 uses it for tar).

- [ ] **Step 1: Write the failing test**

Create `test/unit/input_decoding_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class InputDecodingTest < Minitest::Test

  Input = Metacrunch::Input
  Formats = Metacrunch::Input::Formats

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_gzip_is_detected_by_content_whatever_the_name
    path = write("records.jsonl", gzip("1\n2\n"))

    assert_equal [[path, "1\n2\n"]], documents(path)
  end

  def test_gzip_on_stdin_and_from_ios
    original = $stdin
    $stdin = StringIO.new(gzip("in\n"))

    assert_equal [["-", "in\n"]], documents("-")
    assert_equal [["StringIO", "io\n"]], documents(StringIO.new(gzip("io\n")))
  ensure
    $stdin = original
  end

  def test_all_members_are_read
    assert_equal "1\n2\n3\n", content(write("two.gz", gzip("1\n") + gzip("2\n3\n")))
  end

  def test_a_line_may_span_two_gzip_members
    lines = []
    Input.new(write("split.gz", gzip("1\n2") + gzip("3\n"))).each_document { |s, _| lines.concat(s.each_line.to_a) }

    assert_equal ["1\n", "23\n"], lines
  end

  def test_gzip_inside_gzip_up_to_four_layers
    four = 4.times.reduce("x") { |data, _| gzip(data) }
    path = write("five.gz", gzip(four))

    assert_equal "x", content(write("four.gz", four))
    error = assert_raises(Metacrunch::InputError) { documents(path) }
    assert_equal "#{path}: more than 4 layers of gzip and tar", error.message
  end

  def test_broken_and_truncated_gzip
    data = gzip(Random.new(1).bytes(200_000))
    {"broken" => "#{Formats::GZIP}#{"x" * 20}", "truncated" => data.byteslice(0, data.bytesize / 2),
     "no_footer" => data.byteslice(0, data.bytesize - 4)}.each do |name, bytes|
      path = write("#{name}.gz", bytes)
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_match(/\A#{Regexp.escape(path)}: broken gzip data \(.+\)\z/, error.message)
      assert_kind_of Zlib::Error, error.cause
    end
  end

  def test_data_after_the_gzip_data
    ["garbage", "\0" * 512].each_with_index do |rest, index|
      path = write("rest#{index}.gz", gzip("1\n") + rest)
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_equal "#{path}: data after the end of the gzip data", error.message
    end
  end

  def test_stopping_early_raises_nothing_and_prints_nothing
    data = gzip(Random.new(1).bytes(200_000))
    path = write("cut.gz", data.byteslice(0, data.bytesize - 4))
    _, stderr = capture_io do
      verbose = $VERBOSE
      $VERBOSE = true
      Input.new(path).each_document { |stream, _name| break stream.read(10) }
    ensure
      $VERBOSE = verbose
    end

    assert_empty stderr
    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  def test_unsupported_formats_are_named_with_a_hint
    {"BZh91AY&SY" => "is bzip2 compressed, which metacrunch cannot read; decompress it first, e.g. bzip2 -dc",
     "\xFD7zXZ\x00" => "is xz compressed, which metacrunch cannot read; decompress it first, e.g. xz -dc",
     "\x28\xB5\x2F\xFD" => "is zstd compressed, which metacrunch cannot read; decompress it first, e.g. zstd -dc",
     "PK\x03\x04" => "is a zip archive, which metacrunch cannot read; unpack it first, e.g. unzip -p",
     "PK\x05\x06" => "is a zip archive, which metacrunch cannot read; unpack it first, e.g. unzip -p"}
      .each do |head, text|
      path = write("data", "#{head}rest".b)
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_equal "#{path}: #{text} #{path} | metacrunch run job.rb -i -", error.message
    end
  end

  def test_stdin_and_ios_name_file_in_the_hint
    error = assert_raises(Metacrunch::InputError) { documents(StringIO.new("\x28\xB5\x2F\xFDdata".b)) }

    assert_equal "StringIO: is zstd compressed, which metacrunch cannot read; decompress it first, " \
                 "e.g. zstd -dc FILE | metacrunch run job.rb -i -", error.message
  end

  def test_text_that_looks_a_little_like_a_magic_number_is_plain
    ["BZh is not bzip2\n", "PK is not zip\n", "\x1F\x8B but not deflate".b].each do |text|
      assert_equal text, content(write("plain", text))
    end
  end

  def test_short_and_empty_input
    assert_equal [["StringIO", "abc"]], documents(StringIO.new("abc"))
    assert_equal [["StringIO", ""]], documents(StringIO.new(""))
    assert_equal "", content(write("empty.gz", gzip("")))
  end

  def test_progress_of_gzip_is_the_compressed_position
    input = Input.new(write("random.gz", gzip(Random.new(2).bytes(4 * Input::Stream::BLOCK))))
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_in_delta 1.0, input.progress
  end

  def test_detect
    assert_equal :gzip, Formats.detect(gzip("x").byteslice(0, Formats::PEEK))
    assert_equal :plain, Formats.detect("{\"a\":1}\n")
    assert_equal :plain, Formats.detect("")
    assert_equal "is zstd compressed", Formats.detect("\x28\xB5\x2F\xFD".b).label
  end

  private

  def gzip(text) = Zlib.gzip(text)

  def documents(target)
    result = []
    Input.new(target).each_document { |stream, name| result << [name, stream.read] }
    result
  end

  def content(path) = documents(path).map(&:last).join

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/input_decoding_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Input::Formats`.

- [ ] **Step 3: Implement**

Create `lib/metacrunch/input/formats.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Input
    # Tells gzip and the formats metacrunch cannot read from the first bytes
    # of a document. Internal.
    module Formats

      # How many bytes detection looks at: tar's magic ends at byte 262.
      PEEK = 262
      GZIP = "\x1F\x8B\x08".b

      # A format metacrunch recognizes but cannot read.
      Unsupported = Data.define(:pattern, :label, :advice, :tool) do
        def match?(head) = pattern.match?(head)

        # file: what the hint names, a path or a member's name; nil for
        # stdin and IOs.
        def message(name, file)
          "#{name}: #{label}, which metacrunch cannot read; #{advice} first, " \
            "e.g. #{tool} #{file || "FILE"} | metacrunch run job.rb -i -"
        end
      end

      UNSUPPORTED = [
        Unsupported.new(/\ABZh[1-9](?:1AY&SY|\x17rE8P\x90)/n, "is bzip2 compressed", "decompress it", "bzip2 -dc"),
        Unsupported.new(/\A\xFD7zXZ\x00/n, "is xz compressed", "decompress it", "xz -dc"),
        Unsupported.new(/\A\x28\xB5\x2F\xFD/n, "is zstd compressed", "decompress it", "zstd -dc"),
        Unsupported.new(/\APK(?:\x03\x04|\x05\x06)/n, "is a zip archive", "unpack it", "unzip -p")
      ].freeze

      module_function

      # :gzip, :plain or an Unsupported, for head: the first PEEK bytes of a
      # document (fewer for a short one).
      def detect(head)
        return :gzip if head.start_with?(GZIP)

        UNSUPPORTED.find { it.match?(head) } || :plain
      end

    end
  end
end
```

Create `lib/metacrunch/input/gzip.rb`:

```ruby
# frozen_string_literal: true

require "zlib"

module Metacrunch
  class Input
    # The content of all members of the gzip data in a Stream, as zcat reads
    # it, as the source of another Stream. Internal.
    class Gzip

      def initialize(stream, name)
        @stream = stream
        @name = name
        @gzip = member
      end

      # Raises InputError for broken or truncated data (also when only the
      # footer is missing) and for data after the last member.
      def readpartial(length)
        loop do
          return @gzip.readpartial(length)
        rescue EOFError
          raise unless next_member?
        rescue Zlib::Error => e
          raise InputError, "#{@name}: broken gzip data (#{e.message})"
        end
      end

      # Ends the gzip layer without closing the stream and without checking
      # what was not read. Ending a member in the middle makes zlib warn
      # under -w ("attempt to close unfinished zstream"), so warnings are
      # off meanwhile.
      def finish
        quietly { @gzip.finish } unless @gzip.closed?
      rescue Zlib::Error
        nil
      end

      private

      def quietly
        verbose = $VERBOSE
        $VERBOSE = nil
        yield
      ensure
        $VERBOSE = verbose
      end

      def member
        Zlib::GzipReader.new(@stream)
      rescue Zlib::Error => e
        raise InputError, "#{@name}: broken gzip data (#{e.message})"
      end

      # After a member: puts the bytes it did not use back; true if another
      # member follows.
      def next_member?
        unused = @gzip.unused
        @gzip.finish
        @stream.unread(unused) if unused
        return false if @stream.eof?
        raise InputError, "#{@name}: data after the end of the gzip data" unless @stream.peek(3) == Formats::GZIP

        @gzip = member
        true
      end

    end
  end
end
```

In `lib/metacrunch/input.rb`:

Replace the class comment and add the constant:

```ruby
  # The documents of one or more targets, for sources and other readers:
  # gzip (and, from Task 4, tar) is detected by its content and unpacked,
  # up to MAX_LAYERS deep. Not a source itself: it has each_document, not
  # each. Used from one thread; only #progress may be read from another
  # one. See docs/files.md.
  class Input

    MAX_LAYERS = 4
```

Replace `layers` with:

```ruby
    # Yields the documents of stream. file: what the hint of an unsupported
    # format names (the path, a member's name, or nil); depth: the layers
    # of gzip and tar around stream.
    def layers(stream, name, file, depth, &)
      format = Formats.detect(stream.peek(Formats::PEEK))
      case format
      when :plain then document(stream, name, &)
      when :gzip then gzip(stream, name, file, depth, &)
      else raise InputError, format.message(name, file)
      end
    end
```

Add after `document`:

```ruby
    def gzip(stream, name, file, depth, &)
      deeper(name, depth)
      gzip = Gzip.new(stream, name)
      begin
        layers(Stream.new(gzip), name, file, depth + 1, &)
      ensure
        gzip.finish
      end
    end

    def deeper(name, depth)
      raise InputError, "#{name}: more than #{MAX_LAYERS} layers of gzip and tar" if depth == MAX_LAYERS
    end
```

Add to the requires at the end of the file:

```ruby
require_relative "input/formats"
require_relative "input/gzip"
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -Itest -Ilib test/unit/input_decoding_test.rb`
Expected: all pass, no warnings. Then `bundle exec rake`.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/input.rb lib/metacrunch/input/formats.rb lib/metacrunch/input/gzip.rb \
  test/unit/input_decoding_test.rb
git commit -m "Detect gzip by content in Input, and name formats it cannot read

All members are read as zcat reads them; truncated data, also a missing
footer, and data after the last member raise InputError. bzip2, xz, zstd
and zip raise with a hint to decompress first.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: tar

**Files:**
- Create: `lib/metacrunch/input/tar.rb`
- Modify: `lib/metacrunch/input/formats.rb` (`TAR`, `TAR_AT`, `detect`, comment), `lib/metacrunch/input.rb` (`tar` branch, class comment, require)
- Test: `test/unit/input_tar_test.rb`

**Interfaces:**
- Consumes: `Input#layers`, `#deeper`, `Stream` (`read`, `readpartial(length, outbuf)`, `eof?`), `Stream::BLOCK`.
- Produces: `Formats.detect` returns `:tar` for `ustar` at byte 257. `Input::Tar.new(stream, name)` with `each_member { |stream, name, full_name| }`; `Tar.broken(name, reason)` returns an `InputError`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/input_tar_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tmpdir"

class InputTarTest < Minitest::Test

  Input = Metacrunch::Input

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_every_regular_member_is_a_document
    path = write("records.tar", tar("data/a.jsonl" => "1\n", "data/b.jsonl" => "2\n"))

    assert_equal [["#{path}:data/a.jsonl", "1\n"], ["#{path}:data/b.jsonl", "2\n"]], documents(path)
  end

  def test_tar_gz_with_and_without_a_matching_name
    archive = Zlib.gzip(tar("a.jsonl" => "1\n"))

    ["records.tar.gz", "records.tgz", "records.dat"].each do |name|
      path = write(name, archive)

      assert_equal [["#{path}:a.jsonl", "1\n"]], documents(path)
    end
  end

  def test_members_are_detected_again
    inner = tar("c.jsonl" => "3\n")
    path = write("outer.tar", tar("a.jsonl.gz" => Zlib.gzip("1\n"), "inner.tar" => inner))

    assert_equal [["#{path}:a.jsonl.gz", "1\n"], ["#{path}:inner.tar:c.jsonl", "3\n"]], documents(path)
  end

  def test_directories_links_pax_headers_and_dot_members_are_skipped
    path = write("mixed.tar", tar("d/" => :directory, "link" => :symlink, "PaxHeader/a.jsonl" => :pax,
                                  "._a.jsonl" => "\x00\x05\x16\x07junk", "d/.DS_Store" => "junk",
                                  "a.jsonl" => "1\n"))

    assert_equal [["#{path}:a.jsonl", "1\n"]], documents(path)
  end

  def test_members_read_only_in_part_do_not_disturb_the_next_one
    path = write("records.tar", tar("a.jsonl" => "a" * 3000, "b.jsonl" => "b" * 3000))
    heads = []
    Input.new(path).each_document { |stream, _name| heads << stream.read(2) }

    assert_equal ["aa", "bb"], heads
  end

  def test_an_archive_cut_inside_a_member_s_data
    path = write("cut.tar", tar("a.txt" => "a" * 3000).byteslice(0, 512 + 1000))
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}:a.txt: broken tar archive (ends inside the member's data)", error.message
  end

  def test_a_member_read_only_in_part_is_still_checked
    path = write("cut.tar", tar("a.txt" => "a" * 3000).byteslice(0, 512 + 1000))

    assert_raises(Metacrunch::InputError) { Input.new(path).each_document { |stream, _name| stream.read(10) } }
  end

  def test_an_archive_cut_inside_a_block
    archive = tar("a.txt" => "a" * 3000, "b.txt" => "b" * 3000)

    [512 + 3072 + 100, 512 + 3000 + 10].each do |cut|
      path = write("cut#{cut}.tar", archive.byteslice(0, cut))
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_equal "#{path}: broken tar archive (ends inside a 512-byte block)", error.message
    end
  end

  def test_a_missing_end_marker_is_accepted
    archive = tar("a.txt" => "a" * 3000)
    path = write("noend.tar", archive.byteslice(0, 512 + 3072))

    assert_equal [["#{path}:a.txt", "a" * 3000]], documents(path)
  end

  def test_a_broken_header
    archive = tar("a.txt" => "a")
    archive.setbyte(148, "9".ord)
    path = write("bad.tar", archive)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_match(/\A#{Regexp.escape(path)}: broken tar archive \(.*octal.*\)\z/, error.message)
  end

  def test_tar_counts_as_a_layer
    data = tar("a" => Zlib.gzip(Zlib.gzip(Zlib.gzip(Zlib.gzip("x")))))
    path = write("deep.tar", data)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}:a: more than 4 layers of gzip and tar", error.message
  end

  def test_breaking_out_of_a_nested_member_closes_the_file_quietly
    path = write("records.tgz", Zlib.gzip(tar("a.jsonl.gz" => Zlib.gzip("1\n" * 100_000), "b.jsonl" => "2\n")))
    _, stderr = capture_io do
      verbose = $VERBOSE
      $VERBOSE = true
      Input.new(path).each_document { |stream, _name| break stream.each_line.first }
    ensure
      $VERBOSE = verbose
    end

    assert_empty stderr
    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  def test_macos_tar_archives
    skip "needs /usr/bin/tar (bsdtar)" unless File.executable?("/usr/bin/tar") && RUBY_PLATFORM.include?("darwin")
    source = File.join(@dir, "src")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "a.jsonl"), "1\n")
    path = File.join(@dir, "mac.tgz")
    system("/usr/bin/tar", "-czf", path, "-C", source, "a.jsonl", exception: true)

    assert_equal [["#{path}:a.jsonl", "1\n"]], documents(path)
  end

  def test_progress_of_a_tar_gz
    input = Input.new(write("records.tgz", Zlib.gzip(tar("a.jsonl" => "1\n"))))
    input.each_document { |stream, _name| stream.read }

    assert_in_delta 1.0, input.progress
  end

  private

  def documents(target)
    result = []
    Input.new(target).each_document { |stream, name| result << [name, stream.read] }
    result
  end

  # entries: name => content, or :directory, :symlink, :pax.
  def tar(entries)
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |writer|
      entries.each do |name, content|
        case content
        when :directory then writer.mkdir(name, 0o755)
        when :symlink then writer.add_symlink(name, "a.jsonl", 0o777)
        when :pax then pax(io, name)
        else writer.add_file_simple(name, 0o644, content.bytesize) { it.write(content) }
        end
      end
    end
    io.string
  end

  # A pax header entry (typeflag "x"), as bsdtar writes them.
  def pax(io, name)
    data = "30 path=a-name-longer-than-ustar\n"
    header = Gem::Package::TarHeader.new(name:, mode: 0o644, size: data.bytesize, typeflag: "x", prefix: "",
                                         mtime: 0)
    io.write(header.to_s)
    io.write(data.ljust(512, "\0"))
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/input_tar_test.rb`
Expected: failures: archives are read as one plain document each (names without `:member`).

- [ ] **Step 3: Implement**

Create `lib/metacrunch/input/tar.rb`:

```ruby
# frozen_string_literal: true

require "rubygems/package"

module Metacrunch
  class Input
    # The regular members of the tar archive in a Stream. Uses RubyGems'
    # header parser and entries, but checks what they do not: an archive
    # that ends inside a 512-byte block or inside a member's data is broken.
    # Internal.
    class Tar

      def self.broken(name, reason) = InputError.new("#{name}: broken tar archive (#{reason})")

      def initialize(stream, name)
        @blocks = Blocks.new(stream)
        @name = name
      end

      # Yields a Stream, the name and the full name of every regular member
      # whose base name does not start with ".". A member the block did not
      # read to its end is read to its end afterwards, to check it.
      def each_member
        until @blocks.eof?
          header = next_header
          return if header.empty?

          entry = Gem::Package::TarReader::Entry.new(header, @blocks)
          full_name = full_name(entry)
          member = Member.new(entry, "#{@name}:#{full_name}")
          yield Stream.new(member), member.name, full_name if document?(entry, full_name)
          member.drain
          entry.close
        end
        check_blocks
      end

      private

      def next_header
        check_blocks
        header = Gem::Package::TarHeader.from(@blocks)
        check_blocks
        header
      rescue Gem::Package::TarInvalidError, ArgumentError => e
        check_blocks
        raise Tar.broken(@name, e.message)
      end

      def full_name(entry)
        entry.full_name
      rescue Gem::Package::TarInvalidError => e
        raise Tar.broken(@name, e.message)
      end

      def document?(entry, full_name) = entry.file? && !File.basename(full_name).start_with?(".")

      def check_blocks
        raise Tar.broken(@name, "ends inside a 512-byte block") if @blocks.short?
      end

      # What RubyGems reads a tar archive from: a Stream with a position,
      # noting a read that ended early.
      class Blocks

        attr_reader :pos

        def initialize(stream)
          @stream = stream
          @pos = 0
          @short = false
        end

        def short? = @short

        def eof? = @stream.eof?

        def read(length = nil)
          data = @stream.read(length)
          @short = true if length&.positive? && (data.nil? || data.bytesize < length)
          @pos += data.bytesize if data
          data
        end

        def readpartial(length, outbuf = nil)
          data = @stream.readpartial(length, outbuf)
          @pos += data.bytesize
          data
        end

      end

      # A member's data, as the source of a Stream: raises InputError where
      # the archive ends before the data does.
      class Member

        attr_reader :name

        def initialize(entry, name)
          @entry = entry
          @name = name
        end

        def readpartial(length)
          raise EOFError, "end of member reached" if @entry.eof?

          @entry.readpartial(length)
        rescue EOFError
          raise if @entry.eof?

          raise Tar.broken(@name, "ends inside the member's data")
        end

        # Reads the rest of the member, to check it.
        def drain
          loop { readpartial(Stream::BLOCK) }
        rescue EOFError
          nil
        end

      end

    end
  end
end
```

In `lib/metacrunch/input/formats.rb`: change the module comment to "Tells gzip, tar and the formats metacrunch cannot read …", add the constants after `GZIP`:

```ruby
      TAR = "ustar".b
      TAR_AT = 257
```

and make `detect` (and its comment) return `:tar` too:

```ruby
      # :gzip, :tar, :plain or an Unsupported, for head: the first PEEK
      # bytes of a document (fewer for a short one).
      def detect(head)
        return :gzip if head.start_with?(GZIP)
        return :tar if head.byteslice(TAR_AT, TAR.bytesize) == TAR

        UNSUPPORTED.find { it.match?(head) } || :plain
      end
```

In `lib/metacrunch/input.rb`: the class comment's first sentence becomes "gzip and tar are detected by their content and unpacked, up to MAX_LAYERS deep."; add the branch to `layers`:

```ruby
      when :tar then tar(stream, name, depth, &)
```

add after `gzip`:

```ruby
    def tar(stream, name, depth, &)
      deeper(name, depth)
      Tar.new(stream, name).each_member do |member, member_name, full_name|
        layers(member, member_name, full_name, depth + 1, &)
      end
    end
```

and `require_relative "input/tar"` after `require_relative "input/gzip"`.

Add to `test/unit/input_decoding_test.rb#test_detect`:

```ruby
    header = Gem::Package::TarHeader.new(name: "a", mode: 0o644, size: 0, prefix: "", mtime: 0).to_s

    assert_equal :tar, Formats.detect(header.byteslice(0, Formats::PEEK))
```

(with `require "rubygems/package"` at the top of that test file).

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/input_tar_test.rb test/unit/input_decoding_test.rb`
Expected: all pass, no warnings. Then `bundle exec rake`.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/input.rb lib/metacrunch/input/formats.rb lib/metacrunch/input/tar.rb \
  test/unit/input_tar_test.rb test/unit/input_decoding_test.rb
git commit -m "Read tar archives in Input, one document per regular member

RubyGems' tar reader cuts truncated archives short without an error; the
layer checks for archives that end inside a 512-byte block or inside a
member's data. Members whose names start with a dot (AppleDouble files of
macOS tar, .DS_Store) are skipped.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `Output`

**Files:**
- Create: `lib/metacrunch/output.rb`
- Modify: `lib/metacrunch.rb` (require after `metacrunch/input`)
- Test: `test/unit/output_test.rb`

**Interfaces:**
- Consumes: `Files.name`, `Files.reason`, `STDIO`, `OutputError` (Task 2).
- Produces: `Metacrunch::Output.new(target)`, `#open` (returns self), `#write(string)` (returns nil), `#close`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/output_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class OutputTest < Minitest::Test

  Output = Metacrunch::Output

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  # A pipe that breaks when the buffered data is flushed at the end.
  class PipeClosedBeforeFlush < StringIO

    def flush = raise(Errno::EPIPE)

  end

  # A disk without space.
  class FullDisk < StringIO

    def write(*) = raise(Errno::ENOSPC)

  end

  # Counts flushes.
  class Flushes < StringIO

    attr_reader :flushes

    def flush
      @flushes = (@flushes || 0) + 1
      super
    end

  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.chmod_R(0o755, @dir)
    FileUtils.remove_entry(@dir)
  end

  def test_writes_files_and_pathnames
    path = File.join(@dir, "out.jsonl")
    write_all(path, "a\n", "b\n")
    write_all(Pathname(File.join(@dir, "other.jsonl")), "c\n")

    assert_equal "a\nb\n", File.read(path)
    assert_equal "c\n", File.read(File.join(@dir, "other.jsonl"))
  end

  def test_gz_names_are_compressed_in_any_case
    ["out.jsonl.gz", "OUT.JSONL.GZ"].each do |name|
      path = File.join(@dir, name)
      write_all(path, "a\n")

      assert_equal "a\n", Zlib.gunzip(File.binread(path))
    end
  end

  def test_overwrites_existing_files
    path = File.join(@dir, "out.jsonl")
    File.write(path, "old content\n")
    write_all(path, "new\n")

    assert_equal "new\n", File.read(path)
  end

  def test_names_it_cannot_write_are_refused_before_anything_is_created
    {"out.jsonl.zst" => "metacrunch cannot write zstd; write plain output and compress it, " \
                        "e.g. metacrunch run job.rb | zstd > PATH",
     "out.jsonl.bz2" => "metacrunch cannot write bzip2; write plain output and compress it, " \
                        "e.g. metacrunch run job.rb | bzip2 > PATH",
     "out.jsonl.xz" => "metacrunch cannot write xz; write plain output and compress it, " \
                       "e.g. metacrunch run job.rb | xz > PATH",
     "out.zip" => "metacrunch cannot write zip; write plain output and compress it, " \
                  "e.g. metacrunch run job.rb | zip -q PATH -",
     "out.tar" => "metacrunch cannot write tar archives", "out.tar.gz" => "metacrunch cannot write tar archives",
     "out.tgz" => "metacrunch cannot write tar archives", "OUT.TGZ" => "metacrunch cannot write tar archives"}
      .each do |name, text|
      path = File.join(@dir, name)
      error = assert_raises(Metacrunch::OutputError) { Output.new(path).open }

      assert_equal "#{path}: #{text.sub("PATH", path)}", error.message
      refute_path_exists path
    end
  end

  def test_dash_is_the_stdout_of_open
    stdout, = capture_io { write_all("-", "a\n") }

    assert_equal "a\n", stdout
  end

  def test_ios_from_outside_are_flushed_not_closed
    io = Flushes.new
    write_all(io, "a\n")

    assert_equal ["a\n", 1], [io.string, io.flushes]
    refute_predicate io, :closed?
  end

  def test_a_closed_pipe_raises_sigpipe_once
    output = Output.new(ClosedPipe.new).open
    error = assert_raises(SignalException) { output.write("a\n") }
    output.write("b\n")
    output.close

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_a_pipe_closed_before_the_final_flush_raises_sigpipe
    output = Output.new(PipeClosedBeforeFlush.new).open
    output.write("a\n")

    assert_raises(SignalException) { output.close }
  end

  # The reader takes one byte and goes away; the writer runs into EPIPE.
  def test_a_closed_pipe_of_an_own_fifo_closes_it
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    reader = Thread.new { File.open(fifo) { it.read(1) } }
    output = Output.new(fifo).open
    assert_raises(SignalException) { 100.times { output.write("x" * 65_536) } }
    reader.join
    output.close

    assert(ObjectSpace.each_object(File).none? { it.path == fifo && !it.closed? })
  end

  def test_close_before_open_and_twice_does_nothing
    Output.new(StringIO.new).close
    output = Output.new(StringIO.new).open
    output.close
    output.close
  end

  def test_open_twice_and_write_before_open
    output = Output.new(StringIO.new)

    assert_equal "StringIO: not open", assert_raises(IOError) { output.write("a") }.message
    output.open
    assert_equal "StringIO: already open", assert_raises(Metacrunch::OutputError) { output.open }.message
  end

  def test_errors_on_open
    missing = File.join(@dir, "missing", "out.jsonl")

    assert_equal "#{missing}: no such directory", open_error(missing)
    assert_equal "#{@dir}: is a directory", open_error(@dir)
  end

  def test_no_permission
    skip "root writes everywhere" if Process.uid.zero?
    locked = File.join(@dir, "locked")
    FileUtils.mkdir(locked)
    File.chmod(0o500, locked)
    path = File.join(locked, "out.jsonl")

    assert_equal "#{path}: permission denied", open_error(path)
  end

  def test_errors_while_writing
    output = Output.new(FullDisk.new).open
    error = assert_raises(Metacrunch::OutputError) { output.write("a") }

    assert_equal "OutputTest::FullDisk: no space left on device", error.message
    assert_instance_of Errno::ENOSPC, error.cause
  end

  def test_invalid_targets
    [42, nil, ""].each do |target|
      error = assert_raises(ArgumentError) { Output.new(target) }

      assert_match(/\Aa target must be a path, "-" or an IO, got /, error.message)
    end
  end

  def test_new_creates_nothing
    Output.new(File.join(@dir, "out.jsonl"))

    assert_empty Dir.children(@dir)
  end

  private

  def write_all(target, *strings)
    output = Output.new(target).open
    strings.each { output.write(it) }
    output.close
  end

  def open_error(target) = assert_raises(Metacrunch::OutputError) { Output.new(target).open }.message

end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/output_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Output`.

- [ ] **Step 3: Implement**

Create `lib/metacrunch/output.rb`:

```ruby
# frozen_string_literal: true

require "zlib"

module Metacrunch
  # Where a sink writes: a file (gzip if its name ends with .gz), stdout
  # ("-") or an IO. A closed pipe ends the run as SIGPIPE; own files are
  # closed, IOs from outside only flushed. Used from one thread. See
  # docs/files.md.
  class Output

    GZIP = ".gz"
    ARCHIVES = [".tar", ".tar.gz", ".tgz"].freeze
    # Endings of names whose content metacrunch cannot write: the format,
    # and the command that would write it from plain output.
    COMPRESSORS = {
      ".bz2" => ["bzip2", "bzip2 > PATH"], ".xz" => ["xz", "xz > PATH"], ".zst" => ["zstd", "zstd > PATH"],
      ".zip" => ["zip", "zip -q PATH -"]
    }.freeze

    # target: a path (String or Pathname), "-" for stdout or an IO (anything
    # with write). Checks the type only and touches no file.
    def initialize(target)
      @target = target.is_a?(Pathname) ? target.to_s : target
      unless @target.is_a?(String) ? !@target.empty? : @target.respond_to?(:write)
        raise ArgumentError, "a target must be a path, \"-\" or an IO, got #{target.inspect}"
      end

      @name = Files.name(@target)
      @io = nil
      @file = nil
      @broken = false
    end

    # Creates or truncates a file; "-" is the $stdout of this moment.
    def open
      raise OutputError, "#{@name}: already open" if @io

      @io = output
      self
    end

    # Raises SignalException("PIPE") once when the reader of a pipe went
    # away; afterwards it writes nothing.
    def write(string)
      raise IOError, "#{@name}: not open" unless @io

      guard { @io.write(string) }
      nil
    end

    # Closes an own file, flushes an IO from outside. Does nothing before
    # open and the second time.
    def close
      io = @io
      file = @file
      @io = nil
      @file = nil
      return unless io

      @broken ? discard(io, file) : guard { file ? io.close : flush(io) }
    ensure
      discard(io, file) if file && !file.closed?
    end

    private

    def output
      return $stdout if @target == STDIO
      return @target unless @target.is_a?(String)

      refuse
      @file = File.open(@target, "wb")
      @target.downcase.end_with?(GZIP) ? Zlib::GzipWriter.new(@file) : @file
    rescue Errno::ENOENT
      raise OutputError, "#{@name}: no such directory"
    rescue SystemCallError => e
      raise OutputError, "#{@name}: #{Files.reason(e)}"
    end

    def refuse
      name = @target.downcase
      raise OutputError, "#{@name}: metacrunch cannot write tar archives" if name.end_with?(*ARCHIVES)

      _, (format, command) = COMPRESSORS.find { |ending, _| name.end_with?(ending) }
      return unless format

      raise OutputError, "#{@name}: metacrunch cannot write #{format}; write plain output and compress it, " \
                         "e.g. metacrunch run job.rb | #{command.sub("PATH", @target)}"
    end

    def flush(io)
      io.flush if io.respond_to?(:flush)
    end

    def guard
      return if @broken

      yield
    rescue Errno::EPIPE
      @broken = true
      raise SignalException, "PIPE"
    rescue SystemCallError => e
      raise OutputError, "#{@name}: #{Files.reason(e)}"
    end

    # Closes an own file whose buffer can no longer be written.
    def discard(io, file)
      return unless file

      begin
        io.close unless io.closed?
      rescue Errno::EPIPE, IOError, Zlib::Error
        nil
      end
      file.close unless file.closed?
    end

  end
end
```

In `lib/metacrunch.rb`, after `require_relative "metacrunch/input"`:

```ruby
require_relative "metacrunch/output"
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec ruby -Itest -Ilib test/unit/output_test.rb`
Expected: all pass, no warnings. Then `bundle exec rake`.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/output.rb lib/metacrunch.rb test/unit/output_test.rb
git commit -m "Add Metacrunch::Output for files, stdout and IOs

gzip for names ending with .gz; names of formats it cannot write are
refused before a file is created. A closed pipe raises SIGPIPE once.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: JsonLines on the layer, the CLI, and a benchmark

**Files:**
- Create: `bench/io.rb`
- Modify: `lib/metacrunch/json_lines.rb`, `lib/metacrunch/run_options.rb` (every `JsonLines::STDIO`), `lib/metacrunch/cli/run.rb:31,137`, `lib/metacrunch/cli/trace.rb:36`
- Test: `test/unit/json_lines_reader_test.rb`, `test/cli/run_flags_test.rb`

**Interfaces:**
- Consumes: `Input`, `Output`, `STDIO`, `InputError` (Tasks 2–5).
- Produces: `JsonLines::Reader.new(targets)` (what `Input.new` takes); `JsonLines::Reader#each` without a block is an Enumerator; `JsonLines::Writer.new(target)` (what `Output.new` takes, raises `ArgumentError` for others). `JsonLines::STDIO` no longer exists.

- [ ] **Step 1: Write the benchmark and measure the old code**

Create `bench/io.rb`:

```ruby
# frozen_string_literal: true

# Measures reading and writing JSON Lines through JsonLines::Reader and
# JsonLines::Writer; not part of the test suite.
#
#   bundle exec ruby --yjit -Ilib bench/io.rb [LINES]
#
# Reads LINES lines (default 1 M) from a plain and a gzip file and writes
# up to 300 k of them; best of three runs each.

require "metacrunch"
require "tmpdir"
require "zlib"

module Bench

  LINES = Integer(ARGV.fetch(0, "1000000"))
  WRITTEN = [LINES, 300_000].min

  module_function

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def best(&) = Array.new(3) { seconds(&) }.min

  def report(label, seconds, count)
    per_line = format("%.3f", seconds * 1e6 / count)
    puts "#{label.ljust(16)} #{format("%.3f", seconds).rjust(7)} s #{per_line.rjust(7)} µs/line"
  end

  def record(number) = {"id" => number, "title" => "Title number #{number} " * 3, "year" => number % 120}

  def run
    Dir.mktmpdir do |dir|
      plain = File.join(dir, "records.jsonl")
      File.open(plain, "w") { |file| LINES.times { file.puts(JSON.generate(record(it))) } }
      gzip = File.join(dir, "records.jsonl.gz")
      Zlib::GzipWriter.open(gzip) { |out| File.open(plain, "rb") { IO.copy_stream(it, out) } }

      report("read plain", best { Metacrunch::JsonLines::Reader.new(plain).enum_for(:each).each { nil } }, LINES)
      report("read gzip", best { Metacrunch::JsonLines::Reader.new(gzip).enum_for(:each).each { nil } }, LINES)
      records = Metacrunch::JsonLines::Reader.new(plain).enum_for(:each).first(WRITTEN)
      ctx = Metacrunch::Context.new(id: 1, position: 1, logger: Logger.new(nil))
      output = File.join(dir, "out.jsonl")
      written = best do
        writer = Metacrunch::JsonLines::Writer.new(output)
        writer.open(nil)
        records.each { writer.write(it, ctx) }
        writer.close
      end
      report("write", written, WRITTEN)
    end
  end

end

Bench.run
```

Run (on the unchanged JsonLines): `bundle exec ruby --yjit -Ilib bench/io.rb`
Expected: three lines. Note the numbers for the commit message (the spike measured about 0.33 s plain, 0.46 s gzip, 0.13 s for 300 k writes).

- [ ] **Step 2: Write the failing tests**

In `test/unit/json_lines_reader_test.rb`:

Make `test_progress_grows_while_reading` read a file larger than one block (blocks of 64 KiB):

```ruby
  def test_progress_grows_while_reading
    reader = Reader.new(write("big.jsonl", "\"#{"x" * 10}\"\n" * 30_000))
    values = reader.enum_for(:each).map { reader.progress }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
  end
```

Add:

```ruby
  def test_reads_arrays_of_targets
    assert_equal [1, 2, 3], read(Reader.new([write("a.jsonl", "1\n2\n"), StringIO.new("3\n")]))
  end

  def test_reads_tar_archives_and_gzip_whatever_the_name
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |tar|
      {"a.jsonl" => "1\n", "b.jsonl.gz" => gzip("2\n")}.each do |name, content|
        tar.add_file_simple(name, 0o644, content.bytesize) { it.write(content) }
      end
    end
    path = File.join(@dir, "records.data")
    File.binwrite(path, gzip(io.string))

    assert_equal [1, 2], read(Reader.new(path))
  end

  def test_reads_gzip_from_stdin
    original = $stdin
    $stdin = StringIO.new(gzip("1\n2\n"))

    assert_equal [1, 2], read(Reader.new("-"))
  ensure
    $stdin = original
  end

  def test_each_without_a_block_is_an_enumerator
    assert_equal [1, 2], Reader.new(StringIO.new("1\n2\n")).each.to_a
  end

  def test_a_missing_file_raises_an_input_error
    path = File.join(@dir, "missing.jsonl")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal "#{path}: no such file", error.message
  end
```

and `require "rubygems/package"` at the top.

In `test/cli/run_flags_test.rb` add:

```ruby
  def test_input_reads_tar_gz_archives
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |tar|
      {"a.jsonl" => "1\n2\n", "b.jsonl" => "3\n"}.each do |name, content|
        tar.add_file_simple(name, 0o644, content.bytesize) { it.write(content) }
      end
    end
    input = File.join(@dir, "dump.tar.gz")
    File.binwrite(input, Zlib.gzip(io.string))

    assert_equal [0, "2\n4\n6\n"], cli("run", "-i", input, job("double.rb")).take(2)
  end

  def test_gzip_piped_into_stdin
    assert_equal [0, "2\n4\n"], cli("run", "-i", "-", job("double.rb"), stdin: Zlib.gzip("1\n2\n")).take(2)
    assert_equal [0, "2\n4\n"], cli("run", job("double.rb"), stdin: Zlib.gzip("1\n2\n")).take(2)
  end

  def test_empty_input_gives_no_records
    empty = File.join(@dir, "empty.jsonl.gz")
    File.binwrite(empty, Zlib.gzip(""))

    assert_equal [0, ""], cli("run", job("double.rb"), stdin: "").take(2)
    assert_equal [0, ""], cli("run", "-i", empty, job("double.rb")).take(2)
  end

  def test_a_missing_input_file_ends_the_run
    missing = File.join(@dir, "missing.jsonl")
    code, stdout, stderr = cli("run", "-i", missing, job("double.rb"))

    assert_equal [1, ""], [code, stdout]
    assert_includes stderr, "ERROR Metacrunch::InputError: #{missing}: no such file"
  end

  def test_the_help_of_input_names_gzip_and_tar
    assert_includes cli("help", "run")[1], "(gzip and tar are unpacked)"
  end
```

and `require "rubygems/package"` and `require "zlib"` at the top.

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/json_lines_reader_test.rb test/cli/run_flags_test.rb`
Expected: failures for Arrays (`TypeError` from `File.open`), tar (records are `InvalidRecord`), gzip on stdin and in the CLI, the Enumerator (`LocalJumpError`), the missing file (`Errno::ENOENT`) and the help text. `test_progress_grows_while_reading` may already pass with the old reader, which samples every 1024 lines; it guards the new block-wise counting.

- [ ] **Step 4: Implement**

In `lib/metacrunch/json_lines.rb`:

Replace the file's head comment and requires:

```ruby
# frozen_string_literal: true

require "json"

module Metacrunch
  # A source and sinks for JSON Lines: one JSON value per line. The reader
  # takes what Input takes (paths, "-" for stdin, IOs or an Array of them;
  # gzip and tar are unpacked whatever their names), the writers what
  # Output takes (paths, ".gz" compressed, "-" for stdout, IOs). IO objects
  # are never closed.
  module JsonLines
```

Delete `STDIO = "-"` and `GZIP = ".gz"`.

Replace the `Reader` class (keeping its `parse` method as it is) with:

```ruby
    # Source: yields every line parsed with JSON.parse. A line that is not
    # valid JSON (or not valid UTF-8, or has duplicate keys) is yielded as
    # InvalidRecord, so the job's failure policy decides. Blank lines and byte
    # order marks (also of concatenated files) are skipped.
    class Reader

      BOM = "﻿"
      BLANK = Object.new.freeze
      private_constant :BLANK

      def initialize(targets)
        @input = Input.new(targets)
      end

      # Without a block an Enumerator.
      def each
        return enum_for(:each) unless block_given?

        @input.each_document do |stream, _name|
          stream.each_line do |line|
            line.force_encoding(Encoding::UTF_8)
            line.delete_prefix!(BOM)
            record = parse(line)
            yield record unless record.equal?(BLANK)
          end
        end
      end

      # The share of the input read so far; see Input#progress.
      def progress = @input.progress

      private

      # json accepts invalid UTF-8 inside strings, so the encoding is
      # checked first; a writer would refuse such a record later.
      def parse(line)
        unless line.valid_encoding?
          return InvalidRecord.new(raw: line.chomp, error: JSON::ParserError.new("invalid UTF-8"))
        end

        JSON.parse(line)
      rescue JSON::ParserError => e
        line.b.strip.empty? ? BLANK : InvalidRecord.new(raw: line.chomp, error: e)
      end

    end
```

Delete the class `GzipMembers` and its `private_constant`.

Replace the `Writer` class (keeping `line` as it is) with:

```ruby
    # Sink: writes every record as one line of JSON. Values that are not
    # JSON types (objects, Time, NaN) are refused instead of written as their
    # to_s. A closed pipe (e.g. `| head`) ends the run like SIGPIPE; see
    # Output.
    class Writer

      def initialize(target)
        @output = Output.new(target)
      end

      def open(_context)
        @output.open
      end

      def write(record, ctx)
        @output.write(line(record, ctx))
      end

      def write_batch(records, ctxs)
        @output.write(records.zip(ctxs).map { |record, ctx| line(record, ctx) }.join)
      end

      def close
        @output.close
      end

      private

      def line(record, ctx)
        "#{JSON.generate(record, strict: true)}\n"
      rescue JSON::GeneratorError => e
        raise Error, "record at position #{ctx.position} is not JSON (#{record.class}): #{e.message}"
      end

    end
```

`ContextWriter` stays unchanged.

In `lib/metacrunch/run_options.rb`, `lib/metacrunch/cli/run.rb` and every other file `grep -rn "JsonLines::STDIO" lib test` finds: replace `JsonLines::STDIO` with `STDIO`.

In `lib/metacrunch/cli/run.rb` (line 31) and `lib/metacrunch/cli/trace.rb` (line 36), the `-i` option becomes:

```ruby
        parser.on("-i", "--input PATH", "Read JSON Lines from PATH (- for stdin) instead of the job's source",
                  "(gzip and tar are unpacked)") do |path|
```

(keep the block body of each file as it is).

- [ ] **Step 5: Run the tests and the benchmark**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/json_lines_reader_test.rb test/unit/json_lines_writer_test.rb test/unit/json_lines_context_writer_test.rb test/cli/run_flags_test.rb`
Expected: all pass. Then `bundle exec rake` (everything green, including `run_options_test.rb`, `trace_test.rb` and the help tests).

Run: `bundle exec ruby --yjit -Ilib bench/io.rb`
Expected: reading plain not slower than in Step 1, gzip faster, writing at most 5 % slower. If writing is slower by more, profile `Output#write` (the guard block) before going on.

- [ ] **Step 6: Commit**

```bash
git add bench/io.rb lib/metacrunch/json_lines.rb lib/metacrunch/run_options.rb lib/metacrunch/cli/run.rb \
  lib/metacrunch/cli/trace.rb test/unit/json_lines_reader_test.rb test/cli/run_flags_test.rb
git commit -m "Build JsonLines on Input and Output

The reader takes Arrays of targets and reads gzip (also on stdin) and tar
archives whatever their names; -i dump.tar.gz works. Missing files raise
Metacrunch::InputError with the path.

bench/io.rb, 1 M lines (best of three, before -> after):
  read plain  X.XXX s -> X.XXX s
  read gzip   X.XXX s -> X.XXX s
  write 300 k X.XXX s -> X.XXX s

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(Fill in the measured numbers from Steps 1 and 5.)

---

### Task 7: Generator templates on the layer

**Files:**
- Modify: `lib/metacrunch/templates/source/file.rb.erb`, `lib/metacrunch/templates/sink/file.rb.erb`
- Test: `test/unit/generators_components_test.rb`

**Interfaces:**
- Consumes: `Metacrunch::Input`, `Metacrunch::Output` (Tasks 2–5), `Template.nest` (keeps `require` lines in front of the modules).
- Produces: generated sources take `targets` and have `progress`; generated sinks take `target`.

- [ ] **Step 1: Write the failing tests**

In `test/unit/generators_components_test.rb`, change the two preamble assertions:

```ruby
    assert_match(/\A# frozen_string_literal: true\n\nrequire "metacrunch"\n\nmodule A\n  module B\n    # A source:/,
                 entries.first.content)
```

```ruby
    assert_match(/\A# frozen_string_literal: true\n\nrequire "json"\nrequire "metacrunch"\n\n# A sink:/, content)
```

Add:

```ruby
  def test_a_source_reads_gzip_tar_and_arrays
    in_project do |root|
      write(plan("source", "marc:dump", root:), root)
      File.binwrite(root.join("a.txt.gz"), Zlib.gzip("a\n"))
      io = StringIO.new(+"", "wb")
      Gem::Package::TarWriter.new(io) { |tar| tar.add_file_simple("b.txt", 0o644, 2) { it.write("b\n") } }
      File.binwrite(root.join("b.tar"), io.string)
      source = load_class(root.join("lib/marc/dump.rb"), "Marc::Dump").new([root.join("a.txt.gz"), root.join("b.tar")])

      assert_equal [{"line" => "a"}, {"line" => "b"}], source.enum_for(:each).to_a
      assert_in_delta 1.0, source.progress
    end
  end

  def test_a_sink_compresses_gz_names
    in_project do |root|
      write(plan("sink", "out:json", root:), root)
      sink = load_class(root.join("lib/out/json.rb"), "Out::Json").new(root.join("out.jsonl.gz").to_s)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.close

      assert_equal %({"id":1}\n), Zlib.gunzip(File.binread(root.join("out.jsonl.gz")))
    end
  end

  # Inside a class A::Metacrunch, Metacrunch would be that class itself.
  def test_classes_named_metacrunch_still_reach_the_layer
    in_project do |root|
      write(plan("sink", "out:metacrunch", root:), root)
      write(plan("source", "marc:metacrunch", root:), root)
      sink = load_class(root.join("lib/out/metacrunch.rb"), "Out::Metacrunch").new(root.join("out.jsonl").to_s)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.close
      source = load_class(root.join("lib/marc/metacrunch.rb"), "Marc::Metacrunch").new(root.join("out.jsonl").to_s)

      assert_equal [{"line" => %({"id":1})}], source.enum_for(:each).to_a
    end
  end
```

and `require "rubygems/package"` and `require "zlib"` at the top.

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/generators_components_test.rb`
Expected: the two preamble assertions and the three new tests fail (`Errno::ENOENT` for the Array, gzip read as text, no `progress`).

- [ ] **Step 3: Implement**

Replace `lib/metacrunch/templates/source/file.rb.erb` with:

```erb
# frozen_string_literal: true

require "metacrunch"

# A source: yields a record for each line of its targets: paths, "-" for
# stdin, IOs or an Array of them; gzip and tar are unpacked. The targets
# are read in each, not in new, so that --help, check and tests with
# another source read nothing. In a job:
#   source <%= target.constant %>.new(params.input)
class <%= target.class_name %>

  def initialize(targets)
    @input = ::Metacrunch::Input.new(targets)
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

Replace `lib/metacrunch/templates/sink/file.rb.erb` with:

```erb
# frozen_string_literal: true

require "json"
require "metacrunch"

# A sink: writes each record as a line of JSON to its target: a path, "-"
# for stdout or an IO; a path ending with .gz is compressed. In a job:
#   sink <%= target.constant %>.new(params.output)
class <%= target.class_name %>

  def initialize(target)
    @output = ::Metacrunch::Output.new(target)
  end

  # Called once before the first record.
  def open(_context) = @output.open

  def write(record)
    @output.write("#{::JSON.generate(record)}\n")
  end

  # Optional: with `sink <%= target.constant %>.new(...), batch: 1000` the
  # job calls write_batch with up to 1000 records instead of write.
  # def write_batch(records) = records.each { write(it) }

  # Called at the end, also after an error.
  def close = @output.close

end
```

The test templates (`test.rb.erb`, `path_test.rb.erb`) stay as they are.

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/generators_components_test.rb test/cli/exe_generators_test.rb test/cli/generate_test.rb`
Expected: all pass (the end-to-end test runs the generated tests with `-w` and RuboCop on the generated files). Then `bundle exec rake`.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/templates/source/file.rb.erb lib/metacrunch/templates/sink/file.rb.erb \
  test/unit/generators_components_test.rb
git commit -m "Generate sources and sinks on Input and Output

A generated source reads gzip, tar, stdin and Arrays of files and reports
progress; a generated sink writes .gz and handles closed pipes.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Documentation

**Files:**
- Create: `docs/files.md`
- Modify: `docs/jobs.md` (Sources, Sinks), `docs/cli.md:32`, `docs/workers.md:22-26`, `Readme.md:54-56` and the documentation list (`Readme.md:266-273`), `CHANGELOG.md` (5.0.0 "Added")

**Interfaces:** none (docs only).

- [ ] **Step 1: Write `docs/files.md`**

````markdown
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
member. The stream's methods return binary Strings; the format sets the encoding (`line.force_encoding(Encoding::UTF_8)`).
A stream is valid until the next document. `name` labels the document in messages: the path as given, `-` for stdin,
`dump.tar.gz:records/0001.xml` for a member.

### What is unpacked

The first bytes decide, not the name, for files, stdin and IOs alike:

| Content | |
|---|---|
| gzip | All members are read, as `zcat` reads files written with `cat a.gz b.gz` |
| tar | Every regular member; directories, links and members whose names start with `.` (such as the `._name` files of macOS `tar`) are skipped |
| bzip2, xz, zstd, zip | An error that names the format and the command to decompress it first, e.g. `zstd -dc dump.jsonl.zst \| metacrunch run job.rb -i -` |
| anything else | The document as it is |

Unpacked content is checked again, so `.tar.gz`, a tar of `.gz` files and gzip inside gzip work, up to 4 layers.

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
is read. gzip and tar files that end too early, an interrupted download for example, are errors, not shorter data.

### Progress

With only regular files as targets, `progress` is the share of their bytes read so far (for gzip, of the compressed
bytes), counted in blocks of 64 KiB. A source that returns it from its own `progress` method feeds the progress display
of `metacrunch run`. With stdin, an IO or a FIFO among the targets it is `nil`.

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
````

- [ ] **Step 2: Update the other documents**

`docs/jobs.md`, Sources: replace the sentence "`Metacrunch::JsonLines::Reader.new(path)` reads JSON Lines (`-` for stdin, `.gz` files are decompressed)." with "`Metacrunch::JsonLines::Reader.new(targets)` reads JSON Lines from a path, `-` for stdin, an IO or an Array of them; gzip files and tar archives are unpacked whatever their names (see [Files](files.md))." After the first paragraph of Sources ("Any object with `#each` …"), add the sentence: "A source with `#progress` (0.0 to 1.0) feeds the progress display. A source that reads files is best built on `Metacrunch::Input` (see [Files](files.md))."

`docs/jobs.md`, Sinks: replace "`Metacrunch::JsonLines::Writer.new(path)` writes JSON Lines (`-` for stdout, `.gz` files are compressed)" with "`Metacrunch::JsonLines::Writer.new(target)` writes JSON Lines to a path (`.gz` is compressed), `-` for stdout or an IO". After the first paragraph of Sinks add: "A sink that writes files is best built on `Metacrunch::Output` (see [Files](files.md))."

`docs/cli.md` line 32: the description becomes "Read JSON Lines from PATH (`-` for stdin; gzip and tar are unpacked) instead of the job's source".

`docs/workers.md` lines 22–26: replace "and it does without the reader's handling of `.gz` files, blank lines and invalid UTF-8." with "and it does without the reader's handling of blank lines and invalid UTF-8. Built on `Metacrunch::Input` (see [Files](files.md)), such a source still reads gzip and tar." (Re-wrap the paragraph to 120 columns.)

`Readme.md` lines 54–56: replace "any other source or sink is a small class of your own (see [Sources](docs/jobs.md#sources) and [Sinks](docs/jobs.md#sinks))." with "any other source or sink is a small class of your own (see [Sources](docs/jobs.md#sources) and [Sinks](docs/jobs.md#sinks)), built on `Metacrunch::Input` and `Metacrunch::Output`, which read gzip and tar and take care of stdin, stdout and pipes (see [Files](docs/files.md))."

`Readme.md` documentation list: after the "Jobs" line add "- [Files](docs/files.md): `Metacrunch::Input` and `Metacrunch::Output` for sources and sinks: gzip, tar, stdin, pipes".

`CHANGELOG.md`, 5.0.0 "Added": replace the bullet "`Metacrunch::JsonLines` reader and writers (also gzip); `Metacrunch::InvalidRecord` for records a source cannot read." with:

```markdown
- `Metacrunch::JsonLines` reader and writers; `Metacrunch::InvalidRecord` for records a source cannot read. The reader
  takes Arrays of files and reads gzip and tar archives whatever their names, also on stdin (`-i dump.tar.gz`).
- `Metacrunch::Input` and `Metacrunch::Output` for sources and sinks: paths, `-`, IOs (and Arrays for input); gzip and
  tar detected by content and unpacked; bzip2, xz, zstd and zip named in the error; all paths checked before reading;
  progress; a closed pipe ends the run as SIGPIPE. Problems raise `Metacrunch::InputError` and
  `Metacrunch::OutputError` with the file name. `metacrunch generate source|sink` builds on them.
```

- [ ] **Step 3: Check**

Run: `grep -rn "JsonLines::STDIO\|\.gz. files are decompressed\|\.gz. files are compressed" lib test docs Readme.md examples`
Expected: no output (the old wording is gone; `docs/superpowers/` may still show the old text and is history).

Run: `bundle exec rake`
Expected: tests, coverage and RuboCop green.

- [ ] **Step 4: Commit**

```bash
git add docs/files.md docs/jobs.md docs/cli.md docs/workers.md Readme.md CHANGELOG.md
git commit -m "Document Metacrunch::Input and Metacrunch::Output

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: metacrunch-marcxml: `Reader` on `Input`

**Files (in the gem worktree):**
- Modify: `lib/metacrunch/marcxml/reader.rb`, `bench/parse.rb`
- Test: `test/unit/reader_test.rb`

**Interfaces:**
- Consumes: core `Metacrunch::Input`, `InputError` (Tasks 2–4), through `METACRUNCH_PATH`.
- Produces: `Marcxml::Reader.new(targets, parse: true, normalize: nil)` unchanged in signature; errors of whole inputs are `Metacrunch::InputError`.

- [ ] **Step 1: Create the gem worktree and measure the old reader**

```bash
git -C /Users/renspr/Code/Projects/upb/metacrunch/metacrunch-marcxml worktree add .claude/worktrees/metacrunch-ng-io -b metacrunch-ng-io metacrunch-ng
```

All gem commands below run in `/Users/renspr/Code/Projects/upb/metacrunch/metacrunch-marcxml/.claude/worktrees/metacrunch-ng-io` with `METACRUNCH_PATH=/Users/renspr/Code/Projects/upb/metacrunch/metacrunch/.claude/worktrees/metacrunch-ng-io`. If this session cannot run git in the gem repository, run Tasks 9 and 10 in a session started there. `Gemfile.lock` is ignored by the gem's `.gitignore`.

Add to `bench/parse.rb`, after the line `measure("each_xml (from a file)") { … }`:

```ruby
  measure("Reader (from a file)") { Marcxml::Reader.new(path).each { nil } }
  gzip_path = File.join(dir, "records.xml.gz")
  File.binwrite(gzip_path, Zlib.gzip(File.binread(path)))
  measure("Reader (from a gzip file)") { Marcxml::Reader.new(gzip_path).each { nil } }
```

and `require "zlib"` after `require "tmpdir"`.

Run (old reader, new core): `METACRUNCH_PATH=… bundle exec ruby --yjit -Ilib bench/parse.rb`
Expected: the table with the two new lines; note both Reader values.

- [ ] **Step 2: Change the tests**

In `test/unit/reader_test.rb`:

```ruby
  def test_garbage_after_gzip_data_raises
    path = write("garbage.xml.gz", "#{Zlib.gzip(fixture("collection.xml"))}garbage")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal "#{path}: data after the end of the gzip data", error.message
  end

  def test_a_file_that_is_not_xml_raises
    path = write("data.json", %({"id": 1}\n))
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal %(#{path}: is not XML: it starts with "{\\"id\\": 1}\\n"), error.message
  end

  def test_a_broken_tar_gz_raises
    path = write("broken.tar.gz", Zlib.gzip(tar("a.xml" => fixture("collection.xml"))).byteslice(0, 40))

    assert_match(/broken gzip data/, assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }.message)
  end

  def test_a_file_named_gz_that_is_not_gzip_is_checked_as_xml
    path = write("plain.gz", "not gzip")

    assert_match(/: is not XML/, assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }.message)
  end

  def test_progress
    records = Array.new(3000) { %(<record><controlfield tag="001">#{it}</controlfield></record>) }
    reader = Reader.new(write("many.xml", "<collection>#{records.join("\n")}</collection>"))
    progress = reader.enum_for(:each).map { reader.progress }

    assert_equal progress.sort, progress
    assert(progress.any? { it.positive? && it < 1.0 })
    assert_in_delta 1.0, reader.progress
  end

  def test_missing_files_and_broken_gzip_raise
    missing = File.join(@dir, "missing.xml")

    assert_equal "#{missing}: no such file", assert_raises(Metacrunch::InputError) { read(Reader.new(missing)) }.message
    broken = write("broken.gz", Zlib.gzip(fixture("collection.xml")).byteslice(0, 30))
    assert_match(/broken gzip data/, assert_raises(Metacrunch::InputError) { read(Reader.new(broken)) }.message)
  end
```

Add:

```ruby
  def test_reads_tar_archives_whatever_the_name
    path = write("records.dat", Zlib.gzip(tar("a.xml" => fixture("collection.xml"))))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_skips_members_whose_names_start_with_a_dot
    archive = tar("._a.xml" => "\x00\x05\x16\x07junk", "a.xml" => fixture("collection.xml"))

    assert_equal IDS, ids(read(Reader.new(write("mac.tar", archive))))
  end

  def test_a_truncated_tar_raises
    archive = tar("a.xml" => fixture("collection.xml"))
    path = write("cut.tar", archive.byteslice(0, 2048))
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_match(/broken tar archive \(ends inside the member's data\)/, error.message)
  end

  def test_checks_xml_on_stdin_too
    stdin = $stdin
    $stdin = StringIO.new(%({"id": 1}\n))
    error = assert_raises(Metacrunch::InputError) { read(Reader.new("-")) }

    assert_match(/\A-: is not XML/, error.message)
  ensure
    $stdin = stdin
  end
```

(`test/fixtures/collection.xml` has 2174 bytes; the cut at 2048 lies after the `data/` header, the member's header and 1024 bytes of its data.)

Run: `METACRUNCH_PATH=… bundle exec ruby -Itest -Ilib test/unit/reader_test.rb`
Expected: the changed and new tests fail (old error classes and messages; tar by name only; dot member read; truncation silent; stdin not checked).

- [ ] **Step 3: Implement**

Replace `lib/metacrunch/marcxml/reader.rb` with:

```ruby
# frozen_string_literal: true

require "metacrunch"

module Metacrunch
  module Marcxml
    # A metacrunch source: reads MARCXML from what Metacrunch::Input reads
    # (paths, "-" for stdin, IOs or an Array of them; gzip and tar are
    # unpacked whatever their names) and yields a Record per record, or
    # with parse: false its XML string, which is cheaper to send to workers.
    # A record that cannot be parsed is yielded as Metacrunch::InvalidRecord;
    # a document that does not start like XML raises Metacrunch::InputError.
    class Reader

      BOM = "\xEF\xBB\xBF".b

      # targets: what Metacrunch::Input takes. IOs are never closed.
      def initialize(targets, parse: true, normalize: nil)
        @input = Metacrunch::Input.new(targets)
        Marcxml.check_normalize(normalize)
        if normalize && !parse
          raise ArgumentError, "normalize: needs parse: true; with parse: false normalize in the step that parses: " \
                               "Marcxml.parse(xml, normalize: :nfc)"
        end
        @parse = parse
        @normalize = normalize
      end

      # Without a block an Enumerator.
      def each
        return enum_for(:each) unless block_given?

        @input.each_document do |stream, name|
          check_xml(stream, name)
          Marcxml.each_xml(stream) { |xml| yield(@parse ? record(xml) : xml) }
        end
      end

      # The share of the input read so far; see Metacrunch::Input#progress.
      def progress = @input.progress

      private

      # After a byte order mark and whitespace, a document must start with
      # "<"; an empty one passes.
      def check_xml(stream, name)
        text = stream.peek(64).delete_prefix(BOM).lstrip
        return if text.empty? || text.start_with?("<")

        raise Metacrunch::InputError, "#{name}: is not XML: it starts with #{text[0, 16].inspect}"
      end

      def record(xml)
        Marcxml.parse(xml, normalize: @normalize)
      rescue ParseError => e
        Metacrunch::InvalidRecord.new(raw: xml, error: e)
      end

    end
  end
end
```

- [ ] **Step 4: Run tests, RuboCop and the benchmark**

Run: `METACRUNCH_PATH=… bundle exec rake`
Expected: all tests, coverage and RuboCop green.

Run: `METACRUNCH_PATH=… bundle exec ruby --yjit -Ilib bench/parse.rb`
Expected: "Reader (from a file)" within 5 % of Step 1 (and of the spec's 28.7 µs per record for parse plus split), "Reader (from a gzip file)" not slower.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/marcxml/reader.rb bench/parse.rb test/unit/reader_test.rb
git commit -m "Build the reader on Metacrunch::Input

tar is detected by content, members whose names start with a dot are
skipped, and a truncated tar archive raises instead of losing records.
Errors of whole inputs are Metacrunch::InputError with the file name.

bench/parse.rb (before -> after):
  Reader (from a file)       XX.X -> XX.X µs/record
  Reader (from a gzip file)  XX.X -> XX.X µs/record

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(Fill in the measured numbers.)

---

### Task 10: metacrunch-marcxml: `Writer` on `Output`, Readme and CHANGELOG

**Files (in the gem worktree):**
- Modify: `lib/metacrunch/marcxml/writer.rb`, `Readme.md` (Reader and Writer sections, lines 156–170), `CHANGELOG.md` ("New", the Reader bullet)
- Test: `test/unit/writer_test.rb`

**Interfaces:**
- Consumes: core `Metacrunch::Output`, `OutputError` (Task 5).
- Produces: `Marcxml::Writer.new(target)` takes what `Output.new` takes; `ArgumentError` for others.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/writer_test.rb`:

```ruby
  def test_close_after_a_failed_open_writes_nothing
    writer = Writer.new(File.join(@dir, "missing", "out.xml"))

    assert_raises(Metacrunch::OutputError) { writer.open(nil) }
    writer.close
  end

  def test_rejects_invalid_targets
    assert_raises(ArgumentError) { Writer.new(42) }
  end

  def test_refuses_names_it_cannot_write
    error = assert_raises(Metacrunch::OutputError) { open_writer(File.join(@dir, "out.xml.zst")) }

    assert_match(/cannot write zstd/, error.message)
  end
```

Run: `METACRUNCH_PATH=… bundle exec ruby -Itest -Ilib test/unit/writer_test.rb`
Expected: the three new tests fail (`Errno::ENOENT`, no `ArgumentError`, a zstd name written as plain XML).

- [ ] **Step 2: Implement**

In `lib/metacrunch/marcxml/writer.rb`: remove `require "zlib"`, the constants `STDIO` and `GZIP`, and the private methods `emit`, `guard`, `discard` and `output`. Change the class comment's first sentence to "A metacrunch sink: writes Records as one MARCXML <collection> to what Metacrunch::Output takes: a file (.gz compressed), stdout ("-") or an IO." Replace `initialize`, `open`, `write`, `write_batch` and `close` with:

```ruby
      def initialize(target)
        @output = Metacrunch::Output.new(target)
        @open = false
      end

      def open(_context)
        @output.open
        @open = true
        @output.write(HEADER)
      end

      def write(record, ctx)
        @output.write(xml(record, ctx))
      end

      def write_batch(records, ctxs)
        @output.write(records.zip(ctxs).map { |record, ctx| xml(record, ctx) }.join)
      end

      # Writes the end of the collection, also after an aborted run, and
      # closes the output. Does nothing the second time.
      def close
        return unless @open

        @open = false
        @output.write(FOOTER)
      ensure
        @output.close
      end
```

(`xml` and `record_xml` stay as they are.)

- [ ] **Step 3: Update Readme and CHANGELOG**

`Readme.md`, section "Reader": replace the paragraph that starts "Reads one target or an Array of them" with:

```markdown
Reads what `Metacrunch::Input` reads (see metacrunch's [Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/docs/files.md)):
one target or an Array of them — paths, `"-"` for stdin, or IOs, which it does not close. gzip (all members, as
`zcat` reads them) and tar archives (every regular member, but not those whose names start with `.`) are detected by
their content, whatever their names. A record that is not well-formed becomes a `Metacrunch::InvalidRecord` and fails
under the job's failure policy; the records after it are read. A document that does not start like XML stops the run
with `Metacrunch::InputError`, and so does a record that the end of a file cuts off, e.g. after an interrupted
download. Errors of a whole input (a missing file, broken or truncated gzip or tar data) stop the run with
`Metacrunch::InputError` and the file name. The progress display shows how much of the files has been read.
```

`Readme.md`, section "Writer": after the code line, keep the existing text and add the sentence "Names ending with `.zst`, `.bz2`, `.xz`, `.zip` or `.tar` are refused; see `Metacrunch::Output`."

`CHANGELOG.md`, "New": the Reader bullet becomes:

```markdown
- `Metacrunch::Marcxml::Reader`, a source on `Metacrunch::Input`: files, gzip files (also with several members) and
  tar archives recognized by their content, stdin and IOs; a record that cannot be read becomes a
  `Metacrunch::InvalidRecord`, a truncated gzip or tar file or a document that is not XML raises
  `Metacrunch::InputError`.
```

and the Writer bullet (if there is one) names `Metacrunch::Output`.

- [ ] **Step 4: Run everything**

Run: `METACRUNCH_PATH=… bundle exec rake`
Expected: tests, coverage and RuboCop green.

Run (core worktree): `bundle exec rake`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/marcxml/writer.rb test/unit/writer_test.rb Readme.md CHANGELOG.md
git commit -m "Build the writer on Metacrunch::Output

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## After the last task

Per the workflow: one fresh reviewer on the most capable model reviews both branches (`metacrunch-ng-io` in core from c7ae107, `metacrunch-ng-io` in the gem from ddb2e67) against the spec and this plan. Merging and pushing stay with the user; the gem's CI can only pass after the core branch is in `metacrunch-ng` on GitHub.
