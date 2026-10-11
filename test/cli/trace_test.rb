# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TraceCommandTest < Minitest::Test

  include CliHelper

  CATALOG = File.expand_path("../fixtures/catalog.json", __dir__)

  # stdout whose reader went away (`| head`, quitting less).
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

  end

  def test_traces_the_first_records_without_writing
    Dir.mktmpdir do |dir|
      code, stdout, = cli("trace", "-n", "2", job("catalog.rb"), "--output", dir, CATALOG)

      assert_equal [0, []], [code, Dir.children(dir)]
      assert_match(/\A#1  id=1\n  reject#1    pass\n/, stdout)
      assert_match(/^traced 2 records: 2 to sink, 1 rejected$/, stdout)
    end
  end

  def test_traces_selected_positions
    code, stdout, = cli("trace", "--position", "5", job("catalog.rb"), "--output", "unused", CATALOG)

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
