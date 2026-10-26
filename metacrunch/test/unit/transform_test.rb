# frozen_string_literal: true

require "test_helper"

class TransformTest < Minitest::Test

  SILENT = Logger.new(nil)

  # The statements of a job that a transform refuses.
  JOB_STATEMENTS = {
    "source" => proc { source [] },
    "sink" => proc { sink CollectingSink.new },
    "rejects" => proc { rejects CollectingSink.new },
    "failures" => proc { failures CollectingSink.new },
    "on_failure" => proc { on_failure :skip },
    "profile" => proc { profile true }
  }.freeze

  def test_builds_steps_and_hooks_without_source_and_sinks
    transform = Metacrunch.transform("trim") do
      before { nil }
      map(&:strip)
      reject("Empty", &:empty?)
    end
    pipeline = build(transform)

    assert_equal([["map#1", nil], ["reject#2", "Empty"]], pipeline.steps.map { [it.name, it.reason] })
    assert_equal [nil, nil, nil, nil], [pipeline.source, pipeline.sink, pipeline.rejects, pipeline.failures]
    assert_equal [1, :abort], [pipeline.before_hooks.size, pipeline.on_failure]
  end

  def test_refuses_the_statements_of_jobs
    messages = JOB_STATEMENTS.transform_values do |recipe|
      build(Metacrunch.transform("trim", &recipe))
    rescue ArgumentError => e
      e.message
    end
    expected = JOB_STATEMENTS.keys.to_h do |statement|
      thing = ["rejects", "failures"].include?(statement) ? "#{statement} sink" : statement
      [statement, "transform trim: a transform has no #{thing}; the job that uses it decides"]
    end

    assert_equal expected, messages
  end

  def test_binds_its_params_like_a_job
    transform = Metacrunch.transform("scale") do
      params { param :factor, Integer, default: 2 }

      map { it * params.factor }
    end

    assert_equal 6, build(transform, params: {factor: "3"}).steps.first.call(2, nil)
  end

  def test_params_come_first_in_a_transform_too
    transform = Metacrunch.transform do
      map(&:strip)
      params { param :x }
    end
    error = assert_raises(ArgumentError) { build(transform) }

    assert_equal "params { ... } must be the first statement of a transform", error.message
  end

  def test_describe_stops_at_the_first_statement
    transform = Metacrunch.transform("scale") do
      params { param :factor, Integer, default: 2 }

      raise "must not run"
    end

    assert_equal [:factor], transform.describe.definitions.keys
  end

  def test_names_descriptions_and_labels
    named = Metacrunch.transform("text:trim", desc: "Strip strings") { map(&:strip) }
    loaded = Metacrunch.transform { map(&:strip) }.tap { it.file = "/project/transforms/clean_up.rb" }

    assert_equal ["text:trim", "Strip strings", "text:trim"], [named.name, named.desc, named.label]
    assert_equal ["clean_up", "transform"], [loaded.label, Metacrunch.transform { map(&:strip) }.label]
  end

  def test_names_follow_the_name_rules
    error = assert_raises(ArgumentError) { Metacrunch.transform("Trim") { map(&:strip) } }

    assert_match(/invalid transform name "Trim"/, error.message)
  end

  def test_a_transform_needs_a_recipe
    error = assert_raises(ArgumentError) { Metacrunch::Transform.new("trim") }

    assert_equal "a transform needs a block", error.message
  end

  private

  def build(transform, params: {})
    transform.pipeline(binder: ->(schema) { schema.bind_values(params, env: {}) }, logger: SILENT)
  end

end
