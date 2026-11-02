# frozen_string_literal: true

require "test_helper"

class ProcessorBatchTest < Minitest::Test

  include ProcessorHelper

  # Notes step_in and step_out, as Trace does.
  class RecordingObserver

    attr_reader :events

    def initialize
      @events = []
    end

    def step_in(step, record, _ctx) = @events << [:in, step, record]

    def step_out(step, outputs, _ctx) = @events << [:out, step, outputs]

  end

  def test_runs_the_batch_function_when_the_buffer_is_full_and_on_flush
    calls = []
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 2) do |records|
        calls << records.dup
        records.map { it * 10 }
      end
    end
    (1..5).each { processor.call(it, it) }

    assert_equal [[1, 2], [3, 4]], calls
    processor.flush

    assert_equal [[1, 2], [3, 4], [5]], calls
    assert_equal((1..5).map { [:deliver, it * 10, it] }, outlet.events)
  end

  def test_flush_without_buffered_records_does_nothing
    calls = 0
    processor = build_processor(RecordingOutlet.new) do
      map(batch: 2) do |records|
        calls += 1
        records
      end
    end
    processor.flush

    assert_equal 0, calls
  end

  def test_filter_and_reject_batches_apply_reasons
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      filter("Odd", batch: 3) { |records| records.map(&:even?) }
      reject(batch: 3) { |records| records.map { it == 4 } }
    end
    (1..4).each { processor.call(it, it) }
    processor.flush

    assert_equal [[:reject, 1, "Odd"], [:reject, 3, "Odd"], [:deliver, 2, 2]], outlet.events
  end

  def test_flat_map_batches_stream_children
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) { flat_map(batch: 3) { |records| records.map { [it] * it } } }
    [1, 0, 2].each_with_index { |record, index| processor.call(record, index + 1) }
    processor.flush

    assert_equal [[:deliver, 1, 1], [:deliver, 2, 3], [:deliver, 2, 3]], outlet.events
  end

  def test_an_exception_in_the_results_fails_that_record
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 3) { |records| [records[0], ArgumentError.new("bad"), records[2]] }
      on_failure :skip
    end
    (1..3).each { processor.call(it, it) }

    assert_equal [[:deliver, 1, 1], [:fail, 2, "map#1"], [:deliver, 3, 3]], outlet.events
  end

  def test_a_raising_batch_function_fails_every_record_of_the_batch
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 2) { |_records| raise IOError, "service down" }
      on_failure :skip
    end
    (1..2).each { processor.call(it, it) }

    assert_equal [[:fail, 1, "map#1"], [:fail, 2, "map#1"]], outlet.events
    assert(outlet.errors.all? { it.is_a?(IOError) && it.message == "service down" })
  end

  def test_results_of_another_length_break_the_contract
    messages = contract_messages(->(_records) { [1] }) + contract_messages(->(_records) { {a: 1} })

    wrong_length = "map step map#1 returned 1 result for a batch of 2 records; " \
                   "return an Array with one result per record"
    not_an_array = "map step map#1 returned Hash for a batch of 2 records; return an Array with one result per record"

    assert_equal [wrong_length, wrong_length, not_an_array, not_an_array], messages
  end

  def test_a_batch_of_one_names_one_record
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 1) { |_records| [] }
      on_failure :skip
    end
    processor.call(1, 1)

    assert_equal ["map step map#1 returned 0 results for a batch of 1 record; " \
                  "return an Array with one result per record"], outlet.errors.map(&:message)
  end

  def test_nil_from_a_map_batch_fails_that_record
    messages = contract_messages(->(records) { [records[0], nil] })

    assert_equal ["map step map#1 returned nil"], messages
  end

  def test_reject_bang_in_a_batch_step_breaks_the_contract
    contexts = []
    messages = contract_messages(lambda do |records, ctxs|
      contexts.concat(ctxs)
      ctxs.first.reject!("Nope")
      records
    end)

    assert_equal ["reject! is not available in batch steps; drop records with filter or reject and a reason"] * 2,
                 messages
    refute contexts.any?(&:rejected?)
  end

  def test_reject_bang_works_again_after_a_batch_step
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 1) { |records| records }
      map { |record, ctx| ctx.reject!("Later") && record }
    end
    processor.call(1, 1)

    assert_equal [[:reject, 1, "Later"]], outlet.events
  end

  def test_marks_work_in_batch_steps
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 2) do |records, ctxs|
        ctxs.each { it.mark("Seen") }
        records
      end
    end
    (1..2).each { processor.call(it, it) }

    assert_equal([["Seen"], ["Seen"]], outlet.contexts.map { it.marks.map(&:reason) })
    assert_equal({"Seen" => 2}, processor_stats.snapshot.marked)
  end

  def test_abort_raises_at_the_first_failed_record_after_the_earlier_ones_went_downstream
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) { map(batch: 3) { |records| [records[0], RuntimeError.new("x"), records[2]] } }
    processor.call(1, 1)
    processor.call(2, 2)
    error = assert_raises(Metacrunch::StepError) { processor.call(3, 3) }

    assert_equal 2, error.position
    assert_equal [[:deliver, 1, 1]], outlet.events
  end

  def test_stats_count_input_when_the_batch_runs
    processor = build_processor(RecordingOutlet.new) { map(batch: 5) { |records| records } }
    (1..3).each { processor.call(it, it) }

    assert_equal 0, processor_stats.counter("map#1").input
    processor.flush

    assert_equal [3, 3], [processor_stats.counter("map#1").input, processor_stats.counter("map#1").output]
  end

  def test_profile_adds_the_time_of_each_call
    processor = build_processor(RecordingOutlet.new) do
      profile true
      map(batch: 2) do |records|
        sleep(0.01)
        records
      end
    end
    (1..2).each { processor.call(it, it) }

    assert_operator processor_stats.counter("map#1").time, :>=, 0.01
  end

  def test_an_observer_gets_batches_of_one
    calls = []
    observer = RecordingObserver.new
    processor = build_processor(RecordingOutlet.new, observer:) do
      map(batch: 5) do |records|
        calls << records.dup
        records.map { it * 2 }
      end
    end
    (1..2).each { processor.call(it, it) }

    assert_equal [[1], [2]], calls
    assert_equal [[:in, "map#1", 1], [:out, "map#1", [2]], [:in, "map#1", 2], [:out, "map#1", [4]]],
                 observer.events
  end

  def test_errors_of_later_steps_pass_a_batch_step
    processor = build_processor(RecordingOutlet.new) do
      map(batch: 1) { |records| records }
      map(name: "later") { raise ArgumentError, "later broke" }
    end
    error = assert_raises(Metacrunch::StepError) { processor.call(1, 1) }

    assert_equal "later", error.step
  end

  def test_errors_of_later_steps_pass_a_flat_map_batch
    processor = build_processor(RecordingOutlet.new) do
      flat_map(batch: 1) { |records| records.map { [it, it] } }
      map(name: "later") { raise ArgumentError, "later broke" }
    end
    error = assert_raises(Metacrunch::StepError) { processor.call(1, 1) }

    assert_equal "later", error.step
  end

  def test_a_failing_enumerable_from_a_flat_map_batch_fails_its_record
    outlet = RecordingOutlet.new
    broken = Enumerator.new do |yielder|
      yielder << :child
      raise IOError, "half way"
    end
    processor = build_processor(outlet) do
      flat_map(batch: 2) { |_records| [broken, [:other]] }
      on_failure :skip
    end
    (1..2).each { processor.call(it, it) }

    assert_equal [[:deliver, :child, 1], [:fail, 1, "flat_map#1"], [:deliver, :other, 2]], outlet.events
  end

  def test_a_hash_from_a_flat_map_batch_fails_its_record
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      flat_map(batch: 1) { |records| records.map { {"a" => it} } }
      on_failure :skip
    end
    processor.call(1, 1)

    assert_equal [[:fail, 1, "flat_map#1"]], outlet.events
  end

  def test_flush_runs_buffers_in_step_order
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map(batch: 2) { |records| records.map { it * 10 } }
      map(batch: 3) { |records| records.map { it + 1 } }
    end
    (1..4).each { processor.call(it, it) }
    processor.flush

    assert_equal [[:deliver, 11, 1], [:deliver, 21, 2], [:deliver, 31, 3], [:deliver, 41, 4]], outlet.events
  end

  def test_batch_objects_with_contexts
    lengths = Class.new do
      def self.call_batch(records, ctxs) = records.zip(ctxs).map { |record, ctx| [record, ctx.position] }
    end
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) { map lengths, batch: 2 }
    processor.call(:a, 7)
    processor.call(:b, 8)

    assert_equal [[:deliver, [:a, 7], 7], [:deliver, [:b, 8], 8]], outlet.events
  end

  private

  # The messages of the ContractErrors the records of a batch of two fail with.
  def contract_messages(function)
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map function, batch: 2
      on_failure :skip
    end
    (1..2).each { processor.call(it, it) }

    assert(outlet.errors.all?(Metacrunch::ContractError))
    outlet.errors.map(&:message)
  end

end
