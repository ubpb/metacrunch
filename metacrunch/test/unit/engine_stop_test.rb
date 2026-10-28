# frozen_string_literal: true

require "test_helper"
require "json"

class EngineStopTest < Minitest::Test

  include PipelineHelper

  # Yields 1 and 2, says "ready" on a pipe and waits until stop is called; with ignore_stop it waits for ever.
  class Stoppable

    def initialize(ready, ignore_stop: false)
      @ready = ready
      @ignore_stop = ignore_stop
      @stop = false
    end

    def each
      yield 1
      yield 2
      @ready.puts("ready")
      @ready.flush
      sleep(0.01) until @stop
    end

    def stop
      @stop = true unless @ignore_stop
    end

  end

  # A sink that notes stop, as one that waits (a queue writer that pauses) does.
  class StoppableSink < CollectingSink

    attr_reader :stopped

    def stop
      @stopped = true
    end

  end

  # A source that notes the handler of SIGTERM while it is read.
  class Probe

    attr_reader :handler

    def each
      @handler = Signal.trap("TERM", "DEFAULT")
      Signal.trap("TERM", @handler)
    end

  end

  class StoppableProbe < Probe

    def stop = nil

  end

  def test_sigterm_stops_a_source_that_has_stop_and_the_run_ends_normally
    outcome = run_and_terminate

    assert_equal ["ok", [1, 2], 0], [outcome["status"], outcome["records"], outcome["exitstatus"]]
    assert_includes outcome["log"], "SIGTERM: the source stopped reading; the records read were written"
  end

  def test_sigterm_stops_the_sinks_that_have_stop_too
    assert run_and_terminate["sink_stopped"]
  end

  def test_the_result_says_that_sigterm_stopped_the_source
    assert run_and_terminate["stopped"]
    refute_predicate run_pipeline { source StoppableProbe.new }, :stopped
  end

  def test_with_workers_a_sigterm_to_the_main_process_ends_the_run_normally
    outcome = run_and_terminate(executor: Metacrunch::Executor::Fork.new(workers: 2, batch_size: 3))

    assert_equal ["ok", [1, 2]], [outcome["status"], outcome["records"]]
  end

  def test_a_second_sigterm_stops_at_once
    outcome = run_and_terminate(ignore_stop: true, signals: 2)

    assert_equal "SIGTERM", outcome["signal"]
    assert_equal [1, 2], outcome["records"]
  end

  # A sink that writes inside Thread.handle_interrupt(Object => :never), as one that must not leave a file half
  # written; it says "in" and "finished" on a pipe.
  class Shielded

    def initialize(report)
      @report = report
    end

    def write(_record)
      Thread.handle_interrupt(Object => :never) do
        @report.puts("in")
        @report.flush
        sleep(0.6)
        @report.puts("finished")
        @report.flush
      end
    end

  end

  def test_a_second_sigterm_waits_for_a_block_that_holds_interrupts_back
    skip "needs Process.fork" unless Process.respond_to?(:fork)

    lines = shielded_run

    assert_equal ["in", "finished", "SIGTERM"], lines
  end

  def test_no_handler_for_a_source_without_stop
    probe = Probe.new
    run_pipeline { source probe }

    assert_equal "DEFAULT", probe.handler
  end

  def test_no_handler_when_sigterm_is_trapped
    own = proc {}
    Signal.trap("TERM", own)
    probe = StoppableProbe.new
    run_pipeline { source probe }

    assert_same own, probe.handler
    assert_same own, Signal.trap("TERM", "DEFAULT")
  ensure
    Signal.trap("TERM", "DEFAULT")
  end

  def test_no_handler_off_the_main_thread
    probe = StoppableProbe.new
    Thread.new { run_pipeline { source probe } }.join

    assert_equal "DEFAULT", probe.handler
  end

  def test_the_previous_handler_is_back_after_the_run
    probe = StoppableProbe.new
    run_pipeline { source probe }

    assert_kind_of Proc, probe.handler
    assert_equal "DEFAULT", Signal.trap("TERM", "DEFAULT")
  end

  # A source that installs a handler of its own while it runs keeps it.
  class Trapping

    attr_reader :own

    def each
      @own = proc {}
      Signal.trap("TERM", @own)
    end

    def stop = nil

  end

  def test_a_handler_installed_during_the_run_stays
    source = Trapping.new
    run_pipeline { source source }

    assert_same source.own, Signal.trap("TERM", "DEFAULT")
  ensure
    Signal.trap("TERM", "DEFAULT")
  end

  def test_the_previous_handler_is_back_after_a_run_that_failed
    result = run_pipeline do
      source StoppableProbe.new
      before { raise "before failed" }
    end

    assert_equal :aborted, result.status
    assert_equal "DEFAULT", Signal.trap("TERM", "DEFAULT")
  end

  private

  # Runs a job with a Stoppable source in a child process, sends it SIGTERM (signals times, 0.3 s apart) once the
  # source is ready, and returns what the child reports: status, records and log, or the signal that ended the run,
  # and its exit status.
  def run_and_terminate(executor: Metacrunch::Executor::Inline.new, ignore_stop: false, signals: 1)
    skip "needs Process.fork" unless Process.respond_to?(:fork)

    terminated(executor, ignore_stop, signals)
  end

  def terminated(executor, ignore_stop, signals)
    ready_reader, ready = IO.pipe
    report_reader, report = IO.pipe
    pid = Process.fork do
      ready_reader.close
      report_reader.close
      report.puts(JSON.generate(child_run(executor, ready, ignore_stop)))
      report.close
      Process.exit!(0)
    end
    [ready, report].each(&:close)
    wait_for(ready_reader)
    signals.times do |index|
      sleep(0.3) if index.positive?
      Process.kill("TERM", pid)
    end
    wait_for(report_reader)
    outcome = JSON.parse(report_reader.read)
    _, status = Process.waitpid2(pid)
    outcome.merge("exitstatus" => status.exitstatus)
  ensure
    [ready_reader, report_reader].each { it&.close unless it&.closed? }
    if pid && status.nil?
      Process.kill("KILL", pid)
      Process.waitpid(pid)
    end
  end

  # Runs a job with a source that ignores stop and a Shielded sink in a child process, sends SIGTERM twice while the
  # sink holds interrupts back, and returns the lines the child wrote: the sink's, then the signal that ended it.
  def shielded_run
    report_reader, report = IO.pipe
    pid = Process.fork do
      report_reader.close
      pipeline = build_pipeline do
        source Stoppable.new(File.open(File::NULL, "w"), ignore_stop: true)
        sink Shielded.new(report)
      end
      begin
        Metacrunch::Engine.new(pipeline).run
      rescue SignalException => e
        report.puts(e.message)
      end
      Process.exit!(0)
    end
    report.close
    wait_for(report_reader)
    lines = [report_reader.gets.chomp]
    2.times do
      Process.kill("TERM", pid)
      sleep(0.1)
    end
    lines.concat(report_reader.read.lines.map(&:chomp))
  ensure
    report_reader&.close
    Process.waitpid(pid) if pid
  end

  def child_run(executor, ready, ignore_stop)
    target = StoppableSink.new
    log = StringIO.new
    pipeline = build_pipeline(logger: Logger.new(log)) do
      source Stoppable.new(ready, ignore_stop:)
      sink target
    end
    result = Metacrunch::Engine.new(pipeline, executor:).run
    {"status" => result.status, "records" => target.records, "log" => log.string, "sink_stopped" => target.stopped,
     "stopped" => result.stopped}
  rescue SignalException => e
    {"signal" => e.message, "records" => target.records}
  end

  def wait_for(io)
    flunk("the child process did not answer within 10 s") unless io.wait_readable(10)
  end

end
