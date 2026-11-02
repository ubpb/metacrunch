# frozen_string_literal: true

require "test_helper"
require "json"

class StepTest < Minitest::Test

  class OneArgument

    def self.call(record) = [record]

  end

  class TwoArguments

    def call(record, ctx) = [record, ctx]

  end

  # callable => what it returns for step.call("r", "ctx")
  CASES = {
    "block_with_one_parameter" => [proc { |record| [record] }, ["r"]],
    "block_using_it" => [proc { [it] }, ["r"]],
    "block_with_two_parameters" => [proc { |record, ctx| [record, ctx] }, ["r", "ctx"]],
    "lambda_with_one_parameter" => [->(record) { [record] }, ["r"]],
    "lambda_with_optional_second_parameter" => [->(record, ctx = nil) { [record, ctx] }, ["r", nil]],
    "method_with_optional_second_parameter" => [method(:Array), ["r"]],
    "block_with_named_splat" => [proc { |*args| args }, ["r", "ctx"]],
    "class_with_self_call" => [OneArgument, ["r"]],
    "object_with_two_parameter_call" => [TwoArguments.new, ["r", "ctx"]]
  }.freeze

  CASES.each do |description, (callable, expected)|
    define_method("test_context_passing_for_#{description}") do
      step = Metacrunch::Step.build(:map, callable, name: "map#1")

      assert_equal expected, step.call("r", "ctx")
    end
  end

  def test_library_methods_with_optional_parameters_get_only_the_record
    to_integer = Metacrunch::Step.build(:map, method(:Integer), name: "map#1")
    to_json = Metacrunch::Step.build(:map, JSON.method(:generate), name: "map#2")

    assert_equal 42, to_integer.call("42", "ctx")
    assert_equal "[1]", to_json.call([1], "ctx")
  end

  def test_symbol_procs_get_only_the_record
    step = Metacrunch::Step.build(:map, :upcase.to_proc, name: "map#1")

    assert_equal "R", step.call("r", "ctx")
  end

  def test_rejects_unknown_kinds_and_non_callables
    assert_raises(ArgumentError) { Metacrunch::Step.build(:each, proc { it }, name: "x") }
    assert_raises(ArgumentError) { Metacrunch::Step.build(:map, "not callable", name: "x") }
  end

  def test_batch_is_nil_by_default
    assert_nil Metacrunch::Step.build(:map, ->(record) { record }, name: "map#1").batch
  end

  def test_batch_takes_a_positive_integer
    [0, -1, 1.5, "2"].each do |value|
      error = assert_raises(ArgumentError) { Metacrunch::Step.build(:map, ->(r) { r }, name: "m", batch: value) }

      assert_equal "map step m: batch must be a positive Integer, got #{value.inspect}", error.message
    end
  end

  def test_batch_needs_call_batch_on_objects
    error = assert_raises(ArgumentError) { Metacrunch::Step.build(:filter, OneArgument, name: "f", batch: 2) }

    assert_equal "filter step f: batch: needs an object with call_batch, or a block", error.message
  end

  def test_call_batch_passes_contexts_to_a_batch_function_that_takes_them
    step = Metacrunch::Step.build(:map, ->(records, ctxs) { records.zip(ctxs) }, name: "m", batch: 2)

    assert step.pass_context
    assert_equal [[1, :a], [2, :b]], step.call_batch([1, 2], [:a, :b])
  end

  def test_call_batch_passes_only_the_records_to_a_block_with_one_parameter
    step = Metacrunch::Step.build(:map, proc { |records| records.map { it * 2 } }, name: "m", batch: 2)

    refute step.pass_context
    assert_equal [2, 4], step.call_batch([1, 2], [:a, :b])
  end

  def test_call_batch_calls_call_batch_of_an_object
    doubler = Class.new { def call_batch(records) = records.map { it * 2 } }.new
    with_contexts = Class.new { def self.call_batch(records, ctxs) = records.zip(ctxs) }

    assert_equal [2, 4], Metacrunch::Step.build(:map, doubler, name: "m", batch: 2).call_batch([1, 2], [nil, nil])
    assert_equal [[1, :a]], Metacrunch::Step.build(:map, with_contexts, name: "m", batch: 1).call_batch([1], [:a])
  end

  def test_an_object_with_call_and_call_batch_runs_per_record_without_batch
    both = Class.new do
      def call(record) = record + 1
      def call_batch(records) = records
    end.new
    step = Metacrunch::Step.build(:map, both, name: "m")

    assert_nil step.batch
    assert_equal 2, step.call(1, nil)
  end

  def test_an_object_with_only_call_batch_needs_batch
    batch_only = Class.new { def call_batch(records) = records }.new

    assert_raises(ArgumentError) { Metacrunch::Step.build(:map, batch_only, name: "m") }
  end

end
