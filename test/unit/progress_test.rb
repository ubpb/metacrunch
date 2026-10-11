# frozen_string_literal: true

require "test_helper"
require "metacrunch/progress"

class ProgressTest < Minitest::Test

  Live = Struct.new(:read, :written, :filtered, :rejected, :failed, :source, :limit)
  Output = Metacrunch::Progress::Output

  # A clock the test moves.
  class Clock

    attr_accessor :now

    def initialize
      @now = 0.0
    end

    def call = now

  end

  # A source that knows how much of it was read (and has no size).
  class ProgressSource

    attr_reader :progress

    def initialize(progress)
      @progress = progress
    end

  end

  # A source whose progress breaks.
  class BrokenProgress

    def progress = raise("progress broke")

  end

  # A source whose size breaks.
  class BrokenSize

    def size = raise("size broke")

  end

  # A source that counts how often its size is asked for.
  class CountedSize

    attr_reader :calls

    def initialize
      @calls = 0
    end

    def size
      @calls += 1
      100
    end

  end

  # stderr of a terminal with 10 columns.
  class NarrowTerminal < StringIO

    def winsize = [24, 10]

  end

  # An IO whose first write fails, like a thread killed while writing.
  class FailingOnce < StringIO

    def write(*)
      return super if @failed

      @failed = true
      raise IOError, "interrupted"
    end

  end

  # A terminal that reports no size, like a fresh PTY.
  class SizelessTerminal < StringIO

    def winsize = [0, 0]

  end

  def setup
    @clock = Clock.new
    @live = Live.new(read: 0, written: 0, filtered: 0, rejected: 0, failed: 0, source: Object.new, limit: nil)
  end

  def test_a_line_without_a_known_total_shows_a_spinner
    progress = start(:line)
    advance(2.0, read: 20_000)

    assert_equal "⠙ 00:00:02  read 20.0k (10.0k/s)  written 0", progress.line
  end

  def test_a_known_total_shows_a_bar_and_the_eta
    @live.source = ProgressSource.new(0.5)
    progress = start(:line)
    advance(10.0, read: 500, written: 490, rejected: 3)

    assert_equal "━━━━━━━━━━────────── 50% 00:00:10 ETA 00:00:10  read 500 (50.0/s)  written 490  rejected 3",
                 progress.line
  end

  def test_the_total_comes_from_the_size_or_the_limit
    @live.source = Array.new(100)
    advance(1.0, read: 25)
    sized = start(:line).line
    @live.source = Object.new
    @live.limit = 50
    limited = start(:line).line

    assert_match(/ 25% /, sized)
    assert_match(/ 50% /, limited)
  end

  def test_unknown_or_infinite_sizes_are_ignored
    @live.source = (1..)
    progress = start(:line)
    advance(1.0, read: 5)

    assert_match(/\A⠙ 00:00:01  read 5 /, progress.line)
  end

  def test_an_error_in_the_display_does_not_reach_the_run
    @live.source = BrokenProgress.new
    progress = Metacrunch::Progress.new(Output.new(StringIO.new), mode: :line, interval: 0.01)
    _stdout, stderr = capture_io do
      progress.start(@live)
      sleep(0.05)
      progress.stop
    end

    assert_empty stderr
  end

  def test_the_size_is_read_once_and_may_fail
    counted = CountedSize.new
    @live.source = counted
    sized = start(:line)
    3.times { sized.line }
    @live.source = BrokenSize.new

    assert_equal 1, counted.calls
    assert_match(/\A⠙ /, start(:line).line)
  end

  def test_the_rate_covers_the_last_seconds
    progress = start(:line)
    advance(10.0, read: 10_000)
    progress.line
    advance(16.0, read: 10_600)

    assert_match(%r{read 10\.6k \(100\.0/s\)}, progress.line)
  end

  def test_log_mode_writes_log_lines_of_its_own
    io = StringIO.new
    progress = Metacrunch::Progress.new(Output.new(io), mode: :log, clock: @clock, thread: false)
    progress.start(@live)
    advance(10.0, read: 100)
    progress.tick

    assert_match(%r{\A\d\d:\d\d:\d\d INFO  progress 00:00:10  read 100 \(10\.0/s\)  written 0\n\z}, io.string)
  end

  def test_the_status_line_is_cleared_before_log_lines
    io = StringIO.new
    output = Output.new(io)
    output.status("working")
    output.write("log line\n")
    output.status("working")
    output.clear_status

    assert_equal "\r\e[2Kworking\r\e[2Klog line\n\r\e[2Kworking\r\e[2K", io.string
  end

  def test_the_status_line_is_cut_to_the_terminal_width
    io = NarrowTerminal.new
    Output.new(io).status("0123456789abc")

    assert_equal "\r\e[2K012345678", io.string
  end

  def test_a_status_line_interrupted_while_written_is_still_cleared
    io = FailingOnce.new
    output = Output.new(io)

    assert_raises(IOError) { output.status("working") }
    output.clear_status

    assert_equal Output::CLEAR, io.string
  end

  def test_a_terminal_without_a_size_gets_the_whole_line
    io = SizelessTerminal.new
    Output.new(io).status("working")

    assert_equal "\r\e[2Kworking", io.string
  end

  def test_the_thread_draws_until_stopped
    io = StringIO.new
    progress = Metacrunch::Progress.new(Output.new(io), mode: :line, interval: 0.01)
    progress.start(@live)
    sleep(0.05)
    progress.stop

    assert_includes io.string, "read 0"
    assert(io.string.end_with?(Output::CLEAR))
  end

  private

  def start(mode)
    progress = Metacrunch::Progress.new(Output.new(StringIO.new), mode:, clock: @clock, thread: false)
    progress.start(@live)
    progress
  end

  def advance(now, **counts)
    @clock.now = now
    counts.each { |name, value| @live[name] = value }
  end

end
