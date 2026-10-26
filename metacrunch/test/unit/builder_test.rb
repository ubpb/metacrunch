# frozen_string_literal: true

require "test_helper"

class BuilderTest < Minitest::Test

  include PipelineHelper

  INVALID_RECIPES = {
    "empty_source" => proc { source },
    "second_source_after_an_id" => proc { source(id: ->(record) { record }); source([]) },
    "second_source" => proc { source([]); source([]) },
    "source_without_each" => proc { source(42) },
    "second_sink" => proc { source([]); sink(CollectingSink.new); sink(CollectingSink.new) },
    "callable_and_block" => proc { source([]); map(->(record) { record }) { it } },
    "neither_callable_nor_block" => proc { source([]); map },
    "duplicate_step_name" => proc { source([]); map(name: "x") { it }; map(name: "x") { it } },
    "reserved_step_name" => proc { source([]); map(name: "source") { it } },
    "reserved_sink_step_name" => proc { source([]); map(name: "sink") { it } },
    "unknown_error_policy" => proc { source([]); on_failure :ignore },
    "max_failures_without_skip" => proc { source([]); on_failure :abort, max_failures: 3 },
    "negative_max_failures" => proc { source([]); on_failure :skip, max_failures: -1 },
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
      on_failure :skip, max_failures: 5
    end
    steps = pipeline.steps.map { [it.kind, it.name, it.reason] }

    assert_equal [[:map, "map#1", nil], [:filter, "filter#2", "Too small"], [:reject, "reject#3", nil],
                  [:flat_map, "explode", nil]], steps
    assert_equal [:skip, 5], [pipeline.on_failure, pipeline.max_failures]
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

  def test_accepts_symbol_reasons_and_zero_max_failures
    pipeline = build_pipeline do
      source []
      reject(:patent) { it }
      on_failure :skip, max_failures: 0
    end

    assert_equal ["patent", 0], [pipeline.steps.first.reason, pipeline.max_failures]
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
    error = assert_raises(ArgumentError) { build_pipeline(params: {index: "x"}) { source [] } }

    assert_equal "unknown parameter :index (known: none)", error.message
  end

  INVALID_RECIPES.each do |description, recipe|
    define_method("test_invalid_recipe_#{description}") do
      assert_raises(ArgumentError) { build_pipeline(&recipe) }
    end
  end

  def test_a_job_may_declare_only_an_id_extractor_or_no_source
    extractor = ->(record) { record["id"] }
    with_id = build_pipeline do
      source id: extractor
      map { it }
    end
    without = build_pipeline { map { it } }

    assert_nil with_id.source
    assert_same extractor, with_id.id_extractor
    assert_nil without.source
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

  def test_failures_and_the_failure_policy
    sink = CollectingSink.new
    pipeline = build_pipeline do
      source []
      failures sink, batch: 5
      on_failure :skip, max_failures: 3
    end

    assert_equal [sink, 5, :skip, 3],
                 [pipeline.failures.sink, pipeline.failures.batch, pipeline.on_failure, pipeline.max_failures]
  end

  def test_the_failure_policy_is_checked
    messages = [-> { on_failure :retry }, -> { on_failure :abort, max_failures: 1 }].map do |statement|
      assert_raises(ArgumentError) { build_pipeline { source []; instance_exec(&statement) } }.message
    end

    assert_equal ["on_failure must be one of [:abort, :skip], got :retry",
                  "max_failures must be a non-negative Integer and needs on_failure :skip"], messages
  end

  def test_the_old_names_are_gone
    [-> { errors CollectingSink.new }, -> { on_error :skip }].each do |statement|
      assert_raises(NoMethodError) { build_pipeline { source []; instance_exec(&statement) } }
    end
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
