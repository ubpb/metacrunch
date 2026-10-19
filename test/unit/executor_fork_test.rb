# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ExecutorForkTest < Minitest::Test

  include PipelineHelper
  include Override
  include ForkVariant::NoWorkerLeft

  # Counts the records it yields.
  class CountingSource

    attr_reader :yielded

    def initialize(records)
      @records = records
      @yielded = 0
    end

    def each
      @records.each do |record|
        @yielded += 1
        yield record
      end
    end

  end

  # Yields one Hash again and again, changed for each record, as readers do
  # that save allocations.
  class ReusingSource

    def each
      row = {}
      (1..5).each do |number|
        row["n"] = number
        yield row
      end
    end

  end

  # A step callable that appends "open PID" and "close PID" to a file.
  class PidLog

    def initialize(path)
      @path = path
    end

    def open(_context) = File.write(@path, "open #{Process.pid}\n", mode: "a")

    def close = File.write(@path, "close #{Process.pid}\n", mode: "a")

    def call(record) = record

  end

  # A sink that writes a header in open and leaves it in its write buffer
  # while the workers start.
  class BufferedFile

    def initialize(path)
      @path = path
    end

    def open(_context)
      @file = File.open(@path, "w")
      @file.write("header\n")
    end

    def write(record) = @file.write("#{record}\n")

    def close = @file.close

  end

  class FailingOpen

    def open(_context) = raise("open broke")

    def call(record) = record

  end

  class FailingClose

    def close = raise("close broke")

    def call(record) = record

  end

  class ExitingOpen

    def open(_context) = exit(4)

    def call(record) = record

  end

  class ExitingClose

    def close = exit(5)

    def call(record) = record

  end

  def executor = Metacrunch::Executor::Fork.new(workers: 3, batch_size: 2)

  def test_records_keep_the_source_order_when_workers_take_different_time
    target = CollectingSink.new
    run_pipeline do
      source((1..12).to_a)
      map do |record|
        sleep(0.02) if record <= 2
        record * 10
      end
      sink target
    end

    assert_equal((1..12).map { it * 10 }, target.records)
  end

  def test_a_source_that_reuses_one_object_gives_the_records_it_yielded
    target = CollectingSink.new
    run_pipeline do
      source ReusingSource.new
      map { {"n" => it["n"] * 10} }
      sink target
    end

    assert_equal([10, 20, 30, 40, 50], target.records.map { it["n"] })
  end

  def test_contexts_reach_the_sinks_with_marks_and_store
    target = CollectingSink.new
    run_pipeline do
      source [1, 2, 3], id: ->(record) { "r#{record}" }
      map do |record, ctx|
        ctx.mark("Seen", value: record)
        ctx.store["double"] = record * 2
        record
      end
      sink target
    end
    contexts = target.contexts.map { [it.id, it.position, it.marks.map(&:value), it.store["double"]] }

    assert_equal [["r1", 1, [1], 2], ["r2", 2, [2], 4], ["r3", 3, [3], 6]], contexts
  end

  def test_runs_with_an_empty_source_and_with_fewer_batches_than_workers
    empty = run_pipeline { source [] }
    few = CollectingSink.new
    run_pipeline do
      source [1, 2, 3]
      sink few
    end

    assert_equal [:ok, 0], [empty.status, empty.stats.read]
    assert_equal [1, 2, 3], few.records
  end

  def test_records_larger_than_a_pipe_buffer_pass_both_ways
    target = CollectingSink.new
    run_pipeline do
      source(Array.new(5) { "x" * 1_000_000 })
      map { "#{it}y" }
      sink target
    end

    assert_equal [1_000_001] * 5, target.records.map(&:size)
  end

  def test_strings_keep_their_bytes_and_encoding
    target = CollectingSink.new
    records = ["Müller", "\xFF\xFE".b, "Ἀθῆναι"]
    run_pipeline do
      source records
      sink target
    end

    assert_equal records, target.records
    assert_equal records.map(&:encoding), target.records.map(&:encoding)
  end

  def test_an_abort_in_the_middle_of_a_batch_counts_the_whole_batch
    failed = CollectingSink.new
    result = run_pipeline do
      source((1..6).to_a)
      map { raise ArgumentError, "bad" }
      failures failed
      on_failure :skip, max_failures: 0
    end

    assert_equal [:aborted, [1]], [result.status, failed.records]
    assert_equal 2, result.stats.read
  end

  def test_log_lines_keep_the_source_order_and_stop_at_an_abort
    io = StringIO.new
    run_pipeline(logger: Metacrunch.build_logger(io)) do
      source((1..6).to_a)
      map do |record, ctx|
        sleep(0.02) if record == 1
        ctx.logger.info("record #{record}")
        raise "boom" if record == 4

        record
      end
    end

    assert_equal ["record 1", "record 2", "record 3", "record 4"], io.string.scan(/record \d/)
  end

  def test_workers_inherit_what_before_hooks_load
    target = CollectingSink.new
    table = nil
    run_pipeline do
      source [1, 2]
      before { table = {1 => "one", 2 => "two"} }
      map { table.fetch(it) }
      sink target
    end

    assert_equal ["one", "two"], target.records
  end

  def test_each_worker_opens_and_closes_its_steps
    Dir.mktmpdir do |dir|
      log = File.join(dir, "steps.log")
      run_pipeline do
        source((1..6).to_a)
        map PidLog.new(log)
      end
      lines = File.readlines(log, chomp: true)
      pids = lines.map { it.split.last }.uniq

      assert_equal 3, pids.size
      refute_includes pids, Process.pid.to_s
      assert_equal(3, lines.count { it.start_with?("close") })
    end
  end

  def test_buffered_output_of_a_sink_is_written_once
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.txt")
      run_pipeline do
        source [1, 2]
        sink BufferedFile.new(path)
      end

      assert_equal "header\n1\n2\n", File.read(path)
    end
  end

  def test_an_open_error_in_a_worker_aborts_before_any_record_is_read
    target = CollectingSink.new
    input = CountingSource.new([1, 2])
    result = run_pipeline do
      source input
      map FailingOpen.new
      sink target
    end

    assert_equal [:aborted, "open broke"], [result.status, result.error.message]
    assert_equal [0, []], [input.yielded, target.records]
  end

  def test_a_close_error_in_a_worker_aborts_after_all_records
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map FailingClose.new
      sink target
    end

    assert_equal [:aborted, "close broke"], [result.status, result.error.message]
    assert_equal [1, 2, 3], target.records
  end

  def test_exit_in_a_step_ends_the_run_like_inline
    pipeline = build_pipeline do
      source [1]
      map { exit 3 }
    end
    error = assert_raises(SystemExit) { engine(pipeline).run }

    assert_equal 3, error.status
  end

  def test_exit_in_a_steps_open_or_close_ends_the_run_like_inline
    opening = build_pipeline do
      source [1]
      map ExitingOpen.new
    end
    closing = build_pipeline do
      source [1]
      map ExitingClose.new
    end
    opened = assert_raises(SystemExit) { engine(opening).run }
    closed = assert_raises(SystemExit) { engine(closing).run }

    assert_equal [4, 5], [opened.status, closed.status]
  end

  def test_close_errors_after_an_abort_are_logged_like_inline
    io = StringIO.new
    result = run_pipeline(logger: Metacrunch.build_logger(io)) do
      source [1, 2]
      map FailingClose.new
      map { raise "boom" }
    end

    assert_equal :aborted, result.status
    assert_equal 1, io.string.scan("closing ExecutorForkTest::FailingClose failed").size
  end

  def test_an_early_abort_stops_feeding_the_workers
    result = run_pipeline do
      source((1..1_000).to_a)
      map { raise "boom" }
    end

    assert_equal [:aborted, 1], [result.status, result.error.position]
  end

  def test_sigterm_to_a_worker_ends_the_run_by_sigterm
    pipeline = build_pipeline do
      source [1, 2]
      map do |record|
        Process.kill("TERM", Process.pid)
        sleep(1)
        record
      end
    end
    error = assert_raises(SignalException) { engine(pipeline).run }

    assert_equal "SIGTERM", error.message
  end

  def test_an_observer_needs_the_inline_executor
    pipeline = build_pipeline { source [1] }
    error = assert_raises(ArgumentError) { engine(pipeline, observer: Object.new).run }

    assert_equal "an observer needs the inline executor", error.message
  end

  def test_arguments_are_checked
    assert_raises(ArgumentError) { Metacrunch::Executor::Fork.new(workers: 1) }
    assert_raises(ArgumentError) { Metacrunch::Executor::Fork.new(workers: 2, batch_size: 0) }
    override(Metacrunch::Executor::Fork, :supported?, -> { false }) do
      assert_raises(ArgumentError) { Metacrunch::Executor::Fork.new(workers: 2) }
    end
  end

end
