# frozen_string_literal: true

require "test_helper"

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
    "lambda_with_optional_second_parameter" => [->(record, ctx = nil) { [record, ctx] }, ["r", "ctx"]],
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

  def test_symbol_procs_get_only_the_record
    step = Metacrunch::Step.build(:map, :upcase.to_proc, name: "map#1")

    assert_equal "R", step.call("r", "ctx")
  end

  def test_rejects_unknown_kinds_and_non_callables
    assert_raises(ArgumentError) { Metacrunch::Step.build(:each, proc { it }, name: "x") }
    assert_raises(ArgumentError) { Metacrunch::Step.build(:map, "not callable", name: "x") }
  end

end
