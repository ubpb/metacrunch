# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "metacrunch/testing"

class TestingInvokeTest < Minitest::Test

  Invocation = Metacrunch::Testing::Invocation

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "jobs/a2c.rb" => <<~RUBY,
      Metacrunch.job "a2c" do
        params { param :api_key, String, credential: "catalog.api_key", required: true }

        source raise("a2c must not run")
      end
    RUBY
    "commands/es.rb" => "Metacrunch.command(\"es:switch-alias\") { run { raise \"must not run\" } }\n",
    "commands/reindex.rb" => <<~RUBY,
      Metacrunch.command "catalog:reindex" do
        params do
          param :alias, String, default: "catalog"
          param :api_key, String, credential: "catalog.api_key"
          args :files, min: 1
        end

        run do
          result = invoke "a2c", "--index", "new", *params.files, workers: 4
          next :kept unless result.ok?

          invoke "es:switch-alias", "--to", "new", params.alias
          :switched
        end
      end
    RUBY
    "commands/tolerant.rb" => <<~RUBY,
      Metacrunch.command "tolerant" do
        run do
          invoke "a2c"
        rescue Metacrunch::InvokeError
          :rescued
        end
      end
    RUBY
    "commands/typo.rb" => "Metacrunch.command(\"typo\") { run { invoke \"a2x\" } }\n"
  }.freeze

  def setup
    @root = File.realpath(Dir.mktmpdir("metacrunch-test"))
    FILES.each { |path, code| write(path, "# frozen_string_literal: true\n\n#{code}") }
    # Unreadable credentials: any attempt to read them would raise.
    write(".metacrunch/credentials.yml.enc", "garbage")
    @project = Metacrunch.load_project(@root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_records_invokes_without_running_them
    run = invoke("catalog:reindex", params: {files: ["a.xml"]})

    assert_equal [:switched, :ok, nil], [run.value, run.status, run.error]
    assert_equal [Invocation.new(name: "a2c", argv: ["--index", "new", "a.xml"], options: {workers: 4}),
                  Invocation.new(name: "es:switch-alias", argv: ["--to", "new", "catalog"], options: {})],
                 run.invoked
  end

  def test_a_status_stub_changes_what_the_command_does
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => :ok_with_failures})

    assert_equal [:kept, :ok_with_failures, ["a2c"]], [run.value, run.status, run.invoked.map(&:name)]
  end

  def test_result_stubs
    result = Metacrunch::Result.new(status: :ok_with_failures, error: nil, stats: Metacrunch::Testing::EMPTY_STATS)
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => result})

    assert_equal :kept, run.value
  end

  def test_callable_stubs_get_the_arguments
    seen = []
    record = lambda do |argv|
      seen << argv
      :ok
    end
    run = invoke("catalog:reindex", params: {files: ["a.xml"]},
                                    stubs: {"a2c" => record, "es:switch-alias" => ->(_argv) { :ignored }})

    assert_equal [:switched, [["--index", "new", "a.xml"]]], [run.value, seen]
  end

  def test_a_stubbed_abort_raises_like_a_real_one
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => :aborted})

    assert_equal [:aborted, Metacrunch::InvokeError], [run.status, run.error.class]
    assert_equal "a2c aborted: RuntimeError: stubbed abort", run.error.message
  end

  def test_a_rescued_abort_finishes_with_failures
    run = invoke("tolerant", stubs: {"a2c" => :aborted})

    assert_equal [:rescued, :ok_with_failures], [run.value, run.status]
  end

  def test_unknown_names_in_the_body_fail_the_run
    run = invoke("typo")

    assert_equal :aborted, run.status
    assert_equal "invoke a2x: unknown command, job or file: a2x", run.error.message
  end

  def test_stubs_for_unknown_names_raise
    error = assert_raises(ArgumentError) { invoke("typo", stubs: {"a2x" => :ok}) }

    assert_equal "stub for unknown job or command: a2x", error.message
  end

  # A mistake in the stubs raises instead of ending the run :aborted, so a
  # test that expects an abort cannot pass by it.
  def test_stubs_for_jobs_must_give_a_status_or_a_result
    errors = [:abort, ->(_argv) { "ok" }].map do |stub|
      assert_raises(ArgumentError) { invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => stub}) }
    end

    assert_equal ["the stub for a2c must give a status Symbol or a Result, got :abort",
                  "the stub for a2c must give a status Symbol or a Result, got \"ok\""], errors.map(&:message)
  end

  def test_params_are_bound_from_a_hash
    assert_raises(Metacrunch::ParamError) { invoke("catalog:reindex") }
  end

  def test_jobs_are_tested_with_testing_run
    error = assert_raises(ArgumentError) { invoke("a2c") }

    assert_equal "a2c is a job; test it with Testing.run", error.message
  end

  private

  def invoke(name, **) = Metacrunch::Testing.invoke(@project, name, **)

  def write(path, content)
    file = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end

end
