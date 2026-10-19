# frozen_string_literal: true

require "test_helper"

class ExecutorForkWorkerTest < Minitest::Test

  include PipelineHelper

  Frame = Metacrunch::Executor::Fork::Frame

  # A step callable that notes open and close.
  class Lifecycle

    attr_reader :log

    def initialize
      @log = []
    end

    def open(_context) = @log << :open

    def close = @log << :close

    def call(record) = record

  end

  class FailingOpen

    def open(_context) = raise("open broke")

    def call(record) = record

  end

  class FailingClose

    def close = raise("close broke")

    def call(record) = record

  end

  def test_sends_ready_a_result_per_batch_and_done
    frames = run_worker([[[1, 2], [10, 20]], [[3], [30]]]) do
      map { it + 1 }
      sink CollectingSink.new
    end
    delivered = frames[1][:events].map { |kind, record, state| [kind, record, state.position] }

    assert_equal([:ready, :batch, :batch, :done], frames.map { it[:type] })
    assert_equal [[:deliver, 11, 1], [:deliver, 21, 2]], delivered
    assert_equal [2, 1], [frames[1][:stats].read, frames[2][:stats].read]
  end

  def test_rejected_and_failed_records_carry_their_context
    frames = run_worker([[[1, 2], [1, 2]]]) do
      reject("One") { it == 1 }
      map { raise ArgumentError, "bad" }
      rejects CollectingSink.new
      on_failure :skip
    end
    events = frames[1][:events].map { |kind, _record, state| [kind, state.rejection&.reason, state.failure&.step] }

    assert_equal [[:reject, "One", nil], [:fail, nil, "map#2"]], events
  end

  def test_records_are_not_sent_to_sinks_the_pipeline_lacks
    frames = run_worker([[[1, 2], [1, 2]]]) { reject("One") { it == 1 } }

    assert_empty frames[1][:events]
  end

  def test_log_lines_become_events_in_order_with_the_records
    logger = Metacrunch.build_logger(StringIO.new)
    frames = run_worker([[[1], [1]]], logger:) do
      map do |record, ctx|
        ctx.logger.info("seen")
        record
      end
      sink CollectingSink.new
    end
    events = frames[1][:events]

    assert_equal [:log, :deliver], events.map(&:first)
    assert_match(/INFO  \[#1\] seen\n\z/, events.first.last)
  end

  def test_an_abort_ends_the_batch_and_the_worker
    frames = run_worker([[[1, 2], [1, 2]], [[3], [3]]]) do
      map { it == 2 ? raise("boom") : it }
      sink CollectingSink.new
    end

    assert_equal([:ready, :batch], frames.map { it[:type] })
    assert_equal([[:deliver, 1]], frames[1][:events].map { it.first(2) })
    assert_equal ["map#1", 2], [frames[1][:error].step, frames[1][:error].position]
  end

  def test_an_open_error_is_sent_with_ready
    frames = run_worker([[[1], [1]]]) { map FailingOpen.new }

    assert_equal([[:ready, "open broke"]], frames.map { [it[:type], it[:error]&.message] })
  end

  def test_a_close_error_is_sent_with_done
    frames = run_worker([]) { map FailingClose.new }

    assert_equal([[:ready, nil], [:done, "close broke"]], frames.map { [it[:type], it[:error]&.message] })
  end

  def test_opens_and_closes_the_step_callables
    step = Lifecycle.new
    run_worker([[[1], [1]]]) { map step }

    assert_equal [:open, :close], step.log
  end

  def test_a_signal_closes_the_steps_and_is_raised_again
    step = Lifecycle.new
    pipeline = build_pipeline do
      map step
      map { raise Interrupt }
    end

    assert_raises(Interrupt) { drive(pipeline, [[[1], [1]]]) }
    assert_equal [:open, :close], step.log
  end

  def test_an_exit_in_a_step_is_sent_as_the_error
    frames = run_worker([[[1], [1]]]) { map { exit 3 } }

    assert_equal [SystemExit, 3], [frames[1][:error].class, frames[1][:error].status]
  end

  def test_a_record_that_cannot_be_dumped_ends_the_worker
    frames = run_worker([[[1, 2], [1, 2]], [[3], [3]]]) do
      map { it == 2 ? -> {} : it }
      sink CollectingSink.new
    end

    assert_equal([:ready, :batch], frames.map { it[:type] })
    assert_match(/\Arecord at position 2 cannot be sent from a worker/, frames[1][:error].message)
  end

  private

  def run_worker(batches, logger: SILENT_LOGGER, &)
    drive(build_pipeline(logger:, &), batches)
  end

  # Runs a worker in this process: writes the batches to its input (each
  # record dumped on its own, as Run does), then returns the frames it
  # wrote. The frames of these tests fit in a pipe
  # buffer, so nothing has to read while the worker runs.
  def drive(pipeline, batches)
    input, feed = IO.pipe
    results, output = IO.pipe
    batches.each { |positions, records| Frame.write(feed, Marshal.dump([positions, records.map { Marshal.dump(it) }])) }
    feed.close
    begin
      Metacrunch::Executor::Fork::Worker.new(pipeline).run(input, output)
    ensure
      output.close
    end
    frames = []
    while (frame = Frame.read(results))
      frames << frame
    end
    frames
  ensure
    [input, results].each { it.close unless it.closed? }
  end

end
