# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TraceCommandTest < Minitest::Test

  include CliHelper

  BOOKS = File.expand_path("../fixtures/books.json", __dir__)

  # stdout whose reader went away (`| head`, quitting less).
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

  end

  def test_traces_the_first_records_without_writing
    Dir.mktmpdir do |dir|
      code, stdout, = cli("trace", "-n", "2", job("export_books.rb"), "--output", dir, BOOKS)

      assert_equal [0, []], [code, Dir.children(dir)]
      assert_match(/\A#1  id=1\n  reject#1    pass\n/, stdout)
      assert_match(/^traced 2 records: 2 to sink, 1 rejected$/, stdout)
    end
  end

  def test_traces_selected_positions
    code, stdout, = cli("trace", "--position", "5", job("export_books.rb"), "--output", "unused", BOOKS)

    assert_equal 0, code
    assert_match(/\A#5  id=5\n/, stdout)
    assert_match(/  map#3       failed: KeyError: key not found: "isbns"/, stdout)
  end

  def test_traces_json_lines_from_stdin
    code, stdout, = cli("trace", job("double.rb"), stdin: "1\n{oops\n")

    assert_equal 0, code
    assert_includes stdout, "  map#1   1 → 2\n"
    assert_includes stdout, "  source  failed: JSON::ParserError"
  end

  def test_a_closed_stdout_ends_quietly_with_the_sigpipe_code
    stderr = StringIO.new
    command = Metacrunch::Cli.new(stdin: StringIO.new("1\n2\n"), stdout: ClosedPipe.new, stderr:, env: {})

    assert_equal 141, command.run(["trace", job("double.rb")])
    assert_empty stderr.string
  end

  def test_runs_no_hooks
    code, stdout, = cli("trace", job("hooked.rb"))

    assert_equal 0, code
    assert_match(/^traced 1 record: 1 to sink$/, stdout)
  end

  def test_unpack_chooses_what_the_input_unpacks
    gzipped = Zlib.gzip("1\n")

    assert_match(/^traced 1 record: 1 to sink$/, cli("trace", "--unpack", "gzip", job("double.rb"), stdin: gzipped)[1])
    refute_match(/1 to sink/, cli("trace", "--unpack", "", job("double.rb"), stdin: gzipped)[1])
    assert_match(/--unpack must name gzip, tar or zip, got rar/, cli("trace", "--unpack", "rar", job("double.rb"))[2])
  end

  def test_unpack_needs_input_or_stdin_for_a_job_with_a_source
    code, _stdout, stderr = cli("trace", "--unpack", "zip", job("numbers.rb"), "1")

    assert_equal 2, code
    assert_match(/--unpack applies to -i and to stdin of a job without source/, stderr)
  end

  def test_ids_need_an_id_extractor
    code, _stdout, stderr = cli("trace", "--id", "1", job("double.rb"), stdin: "1\n")

    assert_equal 2, code
    assert_match(/--id needs a job whose source has an id extractor/, stderr)
  end

  # The input is larger than the block of 64 KiB the reader reads ahead.
  def test_repeated_positions_are_traced_once_and_stop_the_source
    input = StringIO.new("1\n" * 100_000)
    _code, stdout, = cli("trace", "--position", "2,2", job("double.rb"), stdin: input)

    assert_match(/^traced 1 record: /, stdout)
    refute_predicate input, :eof?
  end

  def test_usage_errors
    assert_match(/use either --position or --id/, cli("trace", "--position", "1", "--id", "a", job("double.rb"))[2])
    assert_match(/--position needs positive numbers, got x/, cli("trace", "--position", "x", job("double.rb"))[2])
    assert_match(/--limit must be at least 1/, cli("trace", "-n", "0", job("double.rb"))[2])
  end

  def test_an_aborted_trace_exits_with_one
    code, _stdout, stderr = cli("trace", job("chained_error.rb"))

    assert_equal 1, code
    assert_match(/ERROR ArgumentError: source broke/, stderr)
  end

end
