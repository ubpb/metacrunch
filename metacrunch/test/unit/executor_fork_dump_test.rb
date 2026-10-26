# frozen_string_literal: true

require "test_helper"

class ExecutorForkDumpTest < Minitest::Test

  Dump = Metacrunch::Executor::Fork::Dump

  # Marshal cannot dump it: it holds an IO.
  class HoldsIO < StandardError

    def initialize(message = "holds an IO")
      super
      @io = $stderr
    end

  end

  def test_frames_that_can_be_dumped_stay_as_they_are
    frame = {type: :batch, events: [[:deliver, 1, state(1)]], stats: nil, error: nil}
    data, error = Dump.frame(frame)

    assert_nil error
    assert_equal frame, Marshal.load(data)
  end

  def test_exceptions_that_cannot_be_dumped_are_replaced
    failure = Metacrunch::Failure.new(error: raised(HoldsIO.new), step: "map#1")
    frame = {type: :batch, events: [[:fail, 1, state(1, failure:)]], stats: nil, error: raised(HoldsIO.new)}
    data, error = Dump.frame(frame)
    loaded = Marshal.load(data)

    assert_equal ["ExecutorForkDumpTest::HoldsIO", "holds an IO"],
                 [loaded[:events].first.last.failure.error.original_class, error.original_message]
    assert_instance_of Metacrunch::WorkerError, loaded[:error]
    assert_equal frame[:error].backtrace, loaded[:error].backtrace
  end

  def test_a_step_error_keeps_its_class_and_message_with_a_replaced_cause
    step_error = raised(
      Metacrunch::StepError.new(step: "map#1", record_id: "a", position: 3, error: HoldsIO.new),
      cause: raised(HoldsIO.new)
    )
    _data, error = Dump.frame({type: :batch, events: [], stats: nil, error: step_error})

    assert_instance_of Metacrunch::StepError, error
    assert_equal step_error.message, error.message
    assert_instance_of Metacrunch::WorkerError, error.cause
  end

  def test_an_event_that_cannot_be_dumped_ends_the_frame_before_it
    events = [[:deliver, 1, state(1)], [:deliver, -> {}, state(2)], [:deliver, 3, state(3)]]
    data, error = Dump.frame({type: :batch, events:, stats: nil, error: nil})
    loaded = Marshal.load(data)

    assert_equal([1], loaded[:events].map { it[1] })
    assert_match(/\Arecord at position 2 cannot be sent from a worker: no _dump_data is defined for class Proc; /,
                 error.message)
    assert_equal error.message, loaded[:error].message
  end

  def test_finds_the_first_value_that_cannot_be_dumped
    assert_equal 1, Dump.first_undumpable([1, $stderr, -> {}]).first
    assert_nil Dump.first_undumpable([1, 2])
  end

  private

  def state(position, failure: nil)
    Metacrunch::Context::State.new(id: nil, position:, step: "map#1", marks: [], store: {}, rejection: nil, failure:)
  end

  def raised(exception, cause: nil)
    raise exception, cause:
  rescue exception.class => e
    e
  end

end
