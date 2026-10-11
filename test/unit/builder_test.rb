# frozen_string_literal: true

require "test_helper"

class BuilderTest < Minitest::Test

  include PipelineHelper

  INVALID_RECIPES = {
    "missing_source" => proc { map { it } },
    "second_source" => proc { source([]); source([]) },
    "source_without_each" => proc { source(42) },
    "second_sink" => proc { source([]); sink(CollectingSink.new); sink(CollectingSink.new) },
    "callable_and_block" => proc { source([]); map(->(record) { record }) { it } },
    "neither_callable_nor_block" => proc { source([]); map },
    "duplicate_step_name" => proc { source([]); map(name: "x") { it }; map(name: "x") { it } },
    "reserved_step_name" => proc { source([]); map(name: "source") { it } },
    "unknown_error_policy" => proc { source([]); on_error :ignore },
    "max_errors_without_skip" => proc { source([]); on_error :abort, max_errors: 3 },
    "negative_max_errors" => proc { source([]); on_error :skip, max_errors: -1 },
    "params_after_other_statements" => proc { source([]); params { param :x } }
  }.freeze

  def test_builds_a_pipeline_from_the_recipe
    target = CollectingSink.new
    pipeline = build_pipeline do
      source [1, 2], id: ->(record) { record }
      map { it * 2 }
      filter("Too small") { it > 2 }
      reject { it > 100 }
      flat_map(name: "explode") { [it, it] }
      sink target, batch: 10
      on_error :skip, max_errors: 5
    end
    steps = pipeline.steps.map { [it.kind, it.name, it.reason] }

    assert_equal [[:map, "map#1", nil], [:filter, "filter#2", "Too small"], [:reject, "reject#3", nil],
                  [:flat_map, "explode", nil]], steps
    assert_equal [:skip, 5], [pipeline.on_error, pipeline.max_errors]
    assert_same target, pipeline.sink.sink
  end

  def test_accepts_a_reason_or_a_callable_as_first_argument
    callable = ->(record) { record }
    pipeline = build_pipeline do
      source []
      filter callable
      reject "Patent", callable
    end

    assert_equal([[nil, callable], ["Patent", callable]], pipeline.steps.map { [it.reason, it.callable] })
  end

  def test_accepts_symbol_reasons_and_zero_max_errors
    pipeline = build_pipeline do
      source []
      reject(:patent) { it }
      on_error :skip, max_errors: 0
    end

    assert_equal ["patent", 0], [pipeline.steps.first.reason, pipeline.max_errors]
  end

  def test_explains_invalid_reasons
    error = assert_raises(ArgumentError) { build_pipeline { source([]); reject(42, ->(record) { record }) } }

    assert_match(/the reason must be a String or Symbol, got 42/, error.message)
  end

  def test_binds_declared_params
    pipeline = build_pipeline(params: {index: "books"}) do
      params { param :index, String, required: true }
      source [params.index]
    end

    assert_equal ["books"], pipeline.source
  end

  def test_jobs_without_params_reject_given_params
    assert_raises(Metacrunch::ParamError) { build_pipeline(params: {index: "x"}) { source [] } }
  end

  INVALID_RECIPES.each do |description, recipe|
    define_method("test_invalid_recipe_#{description}") do
      assert_raises(ArgumentError) { build_pipeline(&recipe) }
    end
  end

  def test_describe_mode_stops_after_params
    schema = describe do
      params { param :index, String, required: true }
      source raise("the source must not be built in describe mode")
    end

    assert_equal [:index], schema.definitions.keys
  end

  def test_describe_mode_without_params_stops_at_the_first_statement
    schema = describe do
      source []
      raise "the recipe must not continue in describe mode"
    end

    assert_empty schema.definitions
  end

  private

  def describe(&)
    builder = Metacrunch::Builder.new(binder: nil, logger: SILENT_LOGGER, describe: true)
    catch(Metacrunch::Builder::DESCRIBED) do
      builder.instance_exec(&)
      builder.build
    end
  end

end
