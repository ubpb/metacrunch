# frozen_string_literal: true

require "test_helper"

class CommandTest < Minitest::Test

  # Stands in for the Invoker: records invokes and has a root.
  class FakeInvoker

    attr_reader :calls

    def initialize
      @calls = []
    end

    def invoke(target, params: {}, workers: nil, limit: nil, secrets: [])
      @calls << [target, params, {workers:, limit:, secrets: (secrets unless secrets.empty?)}.compact]
      :invoked
    end

    def root = Pathname("/srv/data")

  end

  def test_prepare_binds_the_params_and_the_body_uses_them
    command = Metacrunch.command("greet") do
      params { param :name, String, default: "Ada" }
      run { "Hello, #{params.name}!" }
    end

    assert_equal "Hello, Grace!", call(command, ["--name", "Grace"])
  end

  def test_next_ends_the_body_with_a_value
    command = Metacrunch.command("probe") do
      params { param :skip, :bool, default: false }
      run do
        next :skipped if params.skip

        :done
      end
    end

    assert_equal [:skipped, :done], [call(command, ["--skip"]), call(command, [])]
  end

  def test_the_body_invokes_through_the_invoker_and_knows_the_root
    invoker = FakeInvoker.new
    command = Metacrunch.command("chain") do
      run do
        invoke "a2c", params: {index: "test"}, workers: 2
        root.join("etc")
      end
    end
    value = call(command, [], invoker:)

    assert_equal [["a2c", {index: "test"}, {workers: 2}]], invoker.calls
    assert_equal Pathname("/srv/data/etc"), value
  end

  def test_the_body_gets_the_logger
    logger = Logger.new(nil)
    command = Metacrunch.command("log") { run { logger } }

    assert_same logger, call(command, [], logger:)
  end

  def test_describe_never_runs_the_body
    ran = []
    command = Metacrunch.command("noparams") { run { ran << :body } }
    schema = command.describe

    assert_empty schema.definitions
    assert_empty ran
  end

  def test_describe_returns_the_declared_params
    command = Metacrunch.command("es:create-index") do
      params do
        param :url, String
        args :index, min: 1, max: 1
      end
      run { raise "must not run" }
    end

    assert_equal [:url], command.describe.definitions.keys
  end

  def test_a_command_needs_a_run_block
    command = Metacrunch.command("empty") { params { param :x, String } }
    error = assert_raises(ArgumentError) { prepare(command, []) }

    assert_equal "a command needs run { ... }", error.message
  end

  def test_a_command_has_one_run_block
    command = Metacrunch.command("twice") do
      run { 1 }
      run { 2 }
    end
    error = assert_raises(ArgumentError) { prepare(command, []) }

    assert_equal "run is declared twice; a command has one body", error.message
  end

  def test_run_needs_a_block
    command = Metacrunch.command("blockless") { run }

    assert_raises(ArgumentError) { prepare(command, []) }
  end

  def test_params_must_come_first
    command = Metacrunch.command("late") do
      run { nil }
      params { param :x, String }
    end
    error = assert_raises(ArgumentError) { prepare(command, []) }

    assert_equal "params { ... } must be the first statement of a command", error.message
  end

  def test_invalid_arguments_raise_param_errors
    command = Metacrunch.command("strict") do
      params { param :index, String, required: true }
      run { nil }
    end

    assert_raises(Metacrunch::ParamError) { prepare(command, []) }
  end

  def test_a_command_needs_a_valid_name_and_a_block
    assert_raises(ArgumentError) { Metacrunch.command(nil) { run { nil } } }
    assert_raises(ArgumentError) { Metacrunch::Command.new("nameless") }
  end

  def test_commands_have_a_description
    command = Metacrunch.command("es:create-index", desc: "Create an index") { run { nil } }

    assert_equal ["es:create-index", "Create an index", nil], [command.name, command.desc, command.file]
  end

  private

  def prepare(command, argv)
    command.prepare(binder: ->(schema) { schema.bind_argv(argv, env: {}) })
  end

  def call(command, argv, invoker: FakeInvoker.new, logger: Logger.new(nil))
    prepared = prepare(command, argv)
    scope = Metacrunch::CommandScope.new(params: prepared.params, logger:, invoker:)
    scope.instance_exec(&prepared.body)
  end

end
