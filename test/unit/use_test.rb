# frozen_string_literal: true

require "test_helper"

class UseTest < Minitest::Test

  SILENT = Logger.new(nil)

  # Resolves names from a Hash, as an Invoker resolves them in a project.
  Resolver = Struct.new(:declarations) do
    def resolve(target, **)
      declaration = declarations.fetch(target) do
        raise Metacrunch::ProjectError, "unknown job, transform, command or file: #{target}"
      end
      [declaration, nil]
    end
  end

  SCALE = Metacrunch.transform("scale") do
    params { param :factor, Integer, default: 2 }

    map { it * params.factor }
  end

  TOKEN = Metacrunch.transform("token") do
    params { param :token, String, env: "TOKEN", credential: "api.token", required: true }

    map { params.token }
  end

  def test_inserts_the_steps_of_a_transform_where_it_is_used
    pipeline = build_job({"scale" => SCALE}) do
      source [1, 2]
      map { it + 1 }
      use "scale", params: {factor: 10}
      map { it - 1 }
    end

    assert_equal ["map#1", "scale/map#1", "map#3"], pipeline.steps.map(&:name)
    assert_equal [19, 29], records(pipeline)
  end

  def test_takes_transform_objects_with_their_defaults
    pipeline = build_job do
      source [1]
      use SCALE
    end

    assert_equal [2], records(pipeline)
  end

  def test_the_same_transform_twice_gets_its_own_values_and_a_numbered_prefix
    pipeline = build_job({"scale" => SCALE}) do
      source [1]
      use "scale", params: {factor: 2}
      use "scale", params: {factor: 10}
    end

    assert_equal ["scale/map#1", "scale#2/map#1"], pipeline.steps.map(&:name)
    assert_equal [20], records(pipeline)
  end

  def test_unnamed_transforms_are_prefixed_with_their_file_or_transform
    from_file = Metacrunch.transform { map(&:to_s) }.tap { it.file = "/project/transforms/stringify.rb" }
    pipeline = build_job do
      source [1]
      use from_file
      use(Metacrunch.transform { map(&:to_s) })
    end

    assert_equal ["stringify/map#1", "transform/map#1"], pipeline.steps.map(&:name)
  end

  def test_generated_numbers_count_statements_and_slashes_are_refused
    pipeline = build_job do
      source [1]
      map { it }
      use SCALE
      filter(name: "positive", &:positive?)
      reject { it > 100 }
    end
    error = assert_raises(ArgumentError) { build_job { source [1]; map(name: "a/b") { it } } }

    assert_equal ["map#1", "scale/map#1", "positive", "reject#4"], pipeline.steps.map(&:name)
    assert_equal "the step name a/b contains /, which is reserved for the prefixes of transforms", error.message
  end

  def test_hooks_run_in_the_order_of_their_statements
    events = []
    noting = Metacrunch.transform do
      before { events << :transform_before }
      after { events << :transform_after }
    end
    pipeline = build_job do
      source []
      before { events << :job_before }
      use noting
      after { events << :job_after }
    end
    Metacrunch::Engine.new(pipeline).run

    assert_equal [:job_before, :transform_before, :transform_after, :job_after], events
  end

  def test_steps_and_hooks_see_the_params_of_their_transform
    seen = []
    shout = Metacrunch.transform do
      params { param :mark, String, default: "!" }

      before { seen << params.mark }
      map { "#{it}#{params.mark}" }
    end
    pipeline = build_job(params: {mark: "?"}) do
      params { param :mark, String }

      source ["a"]
      use shout, params: {mark: "!!"}
      map { "#{it}#{params.mark}" }
    end

    assert_equal ["a!!?"], records(pipeline)
    assert_equal ["!!"], seen
  end

  def test_rejected_and_failed_records_name_the_prefixed_step
    checks = Metacrunch.transform("checks") do
      reject("Negative", &:negative?)
      map { 10 / it }
    end
    rejected = CollectingSink.new
    failed = CollectingSink.new
    pipeline = build_job do
      source [-1, 0, 5]
      use checks
      rejects rejected
      errors failed
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline).run

    assert_equal(["checks/reject#1"], rejected.contexts.map { it.rejection.step })
    assert_equal(["checks/map#2"], failed.contexts.map { it.failure.step })
  end

  def test_values_come_first_then_env_then_credentials
    credentials = FakeCredentials.new("api.token" => "credential")
    token = ->(env, values = {}) { records(build_job(env:, credentials:) { source [1]; use TOKEN, params: values }) }

    assert_equal ["given"], token.call({"TOKEN" => "env"}, {token: "given"})
    assert_equal ["env"], token.call({"TOKEN" => "env"})
    assert_equal ["credential"], token.call({})
  end

  def test_unknown_keys_name_the_transform
    error = assert_raises(ArgumentError) { build_job { source []; use SCALE, params: {factr: 3} } }

    assert_equal "use scale: unknown parameter :factr (known: factor)", error.message
  end

  def test_invalid_values_name_the_transform
    error = assert_raises(Metacrunch::ParamError) { build_job { source []; use SCALE, params: {factor: "many"} } }

    assert_equal "use scale: invalid value for factor: \"many\" is not an Integer", error.message
  end

  def test_missing_values_name_the_transform
    error = assert_raises(Metacrunch::ParamError) { build_job { source []; use TOKEN } }

    assert_equal "use token: missing required parameter token (TOKEN unset; api.token: no credentials)",
                 error.message
  end

  def test_use_takes_transforms_only
    declarations = {"export" => Metacrunch.job("export") { source [] },
                    "publish" => Metacrunch.command("publish") { run { nil } }}
    messages = ["export", "publish", Metacrunch.job { source [] }, nil].map do |target|
      build_job(declarations) { source []; use target }
    rescue ArgumentError => e
      e.message
    end

    assert_equal ["use takes transforms; export is a job", "use takes transforms; publish is a command",
                  "use takes transforms; the target is a job",
                  "use takes a transform, its name or its path, got nil"], messages
  end

  def test_unknown_names_raise_project_errors
    error = assert_raises(Metacrunch::ProjectError) { build_job { source []; use "nope" } }

    assert_equal "unknown job, transform, command or file: nope", error.message
  end

  def test_cycles_raise_with_the_chain
    declarations = {}
    declarations["a"] = Metacrunch.transform("a") { use "b" }
    declarations["b"] = Metacrunch.transform("b") { use "a" }
    error = assert_raises(ArgumentError) { build_job(declarations) { source []; use "a" } }

    assert_equal "use cycle: a → b → a", error.message
  end

  def test_nested_transforms_give_nested_prefixes
    inner = Metacrunch.transform("inner") { map { it + 1 } }
    outer = Metacrunch.transform("outer") do
      use inner
      map { it * 2 }
    end
    pipeline = build_job do
      source [1]
      use outer
    end

    assert_equal ["outer/inner/map#1", "outer/map#2"], pipeline.steps.map(&:name)
    assert_equal [4], records(pipeline)
  end

  # A label that looks numbered (a file x#2.rb) never takes a prefix that
  # is in use already.
  def test_prefixes_stay_unique_when_a_label_looks_numbered
    x = Metacrunch.transform("x") { map(&:to_s) }
    numbered = Metacrunch.transform { map(&:to_s) }.tap { it.file = "/project/transforms/x#2.rb" }
    pipeline = build_job do
      source [1]
      use x
      use x
      use numbered
    end

    assert_equal ["x/map#1", "x#2/map#1", "x#2#2/map#1"], pipeline.steps.map(&:name)
  end

  def test_pathnames_are_paths
    pipeline = build_job({"transforms/scale.rb" => SCALE}) do
      source [1]
      use Pathname("transforms/scale.rb")
    end

    assert_equal [2], records(pipeline)
  end

  def test_errors_of_nested_values_name_the_chain
    inner = Metacrunch.transform("inner") do
      params { param :n, Integer, required: true }

      map { it * params.n }
    end
    outer = Metacrunch.transform("outer") { use inner }
    error = assert_raises(Metacrunch::ParamError) { build_job { source []; use outer } }

    assert_equal "use outer → inner: missing required parameter n", error.message
  end

  def test_a_transform_alone_cannot_use_itself
    looping = Metacrunch.transform("loop") { use "loop" }
    binder = ->(schema) { schema.bind_values({}, env: {}) }
    context = context_for({"loop" => looping})
    error = assert_raises(ArgumentError) { looping.pipeline(binder:, logger: SILENT, context:) }

    assert_equal "use cycle: loop → loop", error.message
  end

  def test_values_as_keywords_are_refused
    error = assert_raises(ArgumentError) { build_job({"scale" => SCALE}) { source []; use "scale", factor: 2 } }

    assert_equal "unknown keyword: :factor", error.message
  end

  def test_params_must_be_a_hash
    error = assert_raises(ArgumentError) { build_job({"scale" => SCALE}) { source []; use "scale", params: [2] } }

    assert_equal "use scale: params: must be a Hash, got [2]", error.message
  end

  def test_use_needs_a_context
    job = Metacrunch.job { source []; use SCALE }
    binder = ->(schema) { schema.bind_values({}, env: {}) }
    error = assert_raises(ArgumentError) { job.pipeline(binder:, logger: SILENT) }

    assert_equal "use needs a context: build the job with Job#pipeline(context:)", error.message
  end

  def test_help_never_evaluates_use
    job = Metacrunch.job do
      params { param :index, String }

      use "nope"
    end

    assert_equal [:index], job.describe.definitions.keys
  end

  private

  def context_for(declarations, env: {}, credentials: nil)
    Metacrunch::UseContext.new(resolver: Resolver.new(declarations), env:, credentials:, logger: SILENT)
  end

  # Evaluates a job recipe with params bound from a Hash and names resolved
  # in declarations.
  def build_job(declarations = {}, params: {}, env: {}, credentials: nil, &recipe)
    context = context_for(declarations, env:, credentials:)
    binder = ->(schema) { schema.bind_values(params, env: {}) }
    Metacrunch.job(&recipe).pipeline(binder:, logger: SILENT, context:)
  end

  # The records that reach the sink when pipeline runs.
  def records(pipeline)
    sink = CollectingSink.new
    Metacrunch::Engine.new(pipeline.with(sink: Metacrunch::SinkAdapter.new(sink))).run
    sink.records
  end

end
