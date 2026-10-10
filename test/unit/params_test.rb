# frozen_string_literal: true

require "test_helper"

class ParamsTest < Minitest::Test

  ARGV_ERRORS = {
    "missing_required_value" => [[], /missing required parameter --index/],
    "invalid_integer" => [["--index", "i", "--bulk", "ten", "f"], /invalid value for --bulk: "ten" is not an Integer/],
    "unknown_option" => [["--index", "i", "--color", "red", "f"], /invalid option: --color/],
    "missing_option_value" => [["--index"], /missing argument: --index/],
    "too_few_arguments" => [["--index", "i"], /expected at least 1 argument\(s\) for files, got 0/],
    "too_many_arguments" => [["--index", "i", "a", "b", "c"], /expected at most 2 argument\(s\) for files, got 3/],
    "help_does_not_exit" => [["--index", "i", "--help", "f"], /invalid option: --help/],
    "version_does_not_exit" => [["--index", "i", "--version", "f"], /invalid option: --version/],
    "abbreviated_option" => [["--ind", "i", "f"], /invalid option: --ind/]
  }.freeze

  DECLARATION_ERRORS = {
    "reserved_name" => proc { param :help },
    "duplicate_name" => proc { param :x; param :x },
    "unsupported_type" => proc { param :x, Symbol },
    "default_and_required" => proc { param :x, String, default: "a", required: true },
    "args_twice" => proc { args :a; args :b },
    "min_above_max" => proc { args :a, min: 3, max: 1 },
    "invalid_default" => proc { param :bulk, Integer, default: "ten" },
    "default_of_the_wrong_type" => proc { param :tags, Array, default: 5 },
    "name_shadows_a_params_method" => proc { param :to_h },
    "short_help_option" => proc { param :host, short: "-h" }
  }.freeze

  def test_cli_value_wins_over_environment_and_default
    params = schema { param :url, String, default: "http://default", env: "ES_URL" }
    env = {"ES_URL" => "http://env"}

    assert_equal "http://cli", params.bind_argv(["--url", "http://cli"], env:).url
    assert_equal "http://env", params.bind_argv([], env:).url
    assert_equal "http://default", params.bind_argv([], env: {}).url
  end

  def test_converts_cli_values_to_the_declared_types
    params = schema do
      param :bulk_size, Integer
      param :ratio, Float
      param :verbose, :bool
      param :fields, Array
    end
    values = params.bind_argv(["--bulk-size", "10", "--ratio", "0.5", "--no-verbose", "--fields", "a, b"], env: {})

    assert_equal({bulk_size: 10, ratio: 0.5, verbose: false, fields: ["a", "b"]}, values.to_h)
  end

  def test_converts_environment_values
    params = schema do
      param :verbose, :bool, env: "VERBOSE"
      param :bulk, Integer, env: "BULK"
    end

    assert_equal({verbose: true, bulk: 5}, params.bind_argv([], env: {"VERBOSE" => "yes", "BULK" => "5"}).to_h)
  end

  def test_collects_positional_arguments
    values = job_schema.bind_argv(["--index", "books", "a.xml", "b.xml"], env: {})

    assert_equal({index: "books", bulk: 100, files: ["a.xml", "b.xml"]}, values.to_h)
  end

  ARGV_ERRORS.each do |description, (argv, message)|
    define_method("test_bind_argv_error_#{description}") do
      error = assert_raises(Metacrunch::ParamError) { job_schema.bind_argv(argv, env: {}) }

      assert_match message, error.message
    end
  end

  def test_rejects_arguments_without_args_declaration
    error = assert_raises(Metacrunch::ParamError) { schema { param :x }.bind_argv(["a"], env: {}) }

    assert_match(/unexpected arguments: a/, error.message)
  end

  def test_bind_hash_keeps_typed_values_and_converts_strings
    params = schema do
      param :bulk, Integer
      param :verbose, :bool
      args :files
    end
    values = params.bind_hash(bulk: "10", verbose: true, files: ["a"])

    assert_equal({bulk: 10, verbose: true, files: ["a"]}, values.to_h)
  end

  def test_bind_hash_rejects_unknown_keys_and_wrong_types
    params = schema { param :bulk, Integer }

    assert_raises(Metacrunch::ParamError) { params.bind_hash(color: "red") }
    assert_raises(Metacrunch::ParamError) { params.bind_hash(bulk: 1.5) }
  end

  DECLARATION_ERRORS.each do |description, declaration|
    define_method("test_declaration_error_#{description}") do
      assert_raises(ArgumentError) { schema(&declaration) }
    end
  end

  def test_converts_and_validates_defaults
    params = schema do
      param :bulk, Integer, default: "1000"
      param :ratio, Float, default: 1
      param :dry, :bool, default: "yes"
    end

    assert_equal({bulk: 1000, ratio: 1.0, dry: true}, params.bind_argv([], env: {}).to_h)
  end

  def test_bound_values_are_frozen
    params = schema do
      param :tags, Array, default: ["a"]
      param :fields, Array
    end
    values = params.bind_argv(["--fields", "x,y"], env: {})

    assert_raises(FrozenError) { values.tags << "b" }
    assert_raises(FrozenError) { values.fields.first << "z" }
    assert_equal ["a"], params.bind_argv([], env: {}).tags
  end

  def test_invalid_environment_values_name_the_variable
    params = schema { param :bulk, Integer, env: "BULK" }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {"BULK" => "ten"}) }

    assert_match(/invalid value for --bulk from environment variable BULK: "ten" is not an Integer/, error.message)
  end

  def test_empty_environment_values_count_as_unset
    params = schema { param :bulk, Integer, default: 5, env: "BULK" }

    assert_equal 5, params.bind_argv([], env: {"BULK" => ""}).bulk
  end

  def test_help_is_recognized_only_as_an_option
    params = job_schema

    assert params.help_requested?(["a.xml", "--help"])
    assert params.help_requested?(["-h"])
    refute params.help_requested?(["--index", "-h", "a.xml"])
  end

  def test_explains_names_that_would_hide_params_methods
    error = assert_raises(ArgumentError) { schema { param :to_h } }

    assert_match(/parameter name to_h would hide params\.to_h/, error.message)
  end

  def test_help_lists_options_and_arguments
    help = schema do
      param :index, String, required: true, short: "-i", desc: "Index name"
      param :url, String, default: "http://localhost:9200", env: "ES_URL"
      args :files, min: 1, desc: "Input files"
    end.help

    assert_match(/-i, --index VALUE\s+Index name \(required\)/, help)
    assert_match(%r{--url VALUE\s+\(default: http://localhost:9200, env: ES_URL\)}, help)
    assert_match(/FILES  Input files  \(1 or more arguments\)/, help)
  end

  private

  def schema(&)
    Metacrunch::Params.new.tap { |params| params.instance_exec(&) }
  end

  def job_schema
    schema do
      param :index, String, required: true
      param :bulk, Integer, default: 100
      args :files, min: 1, max: 2
    end
  end

end
