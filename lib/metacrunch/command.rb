# frozen_string_literal: true

module Metacrunch
  # A command: a named recipe that declares parameters and a body,
  # `run { ... }`. Evaluating the recipe binds the parameters; the body
  # runs afterwards on a CommandScope (see Invoker#call).
  class Command

    # The bound parameters and the body of an evaluated recipe.
    Prepared = Data.define(:params, :body)

    attr_reader :name, :desc

    # The file the command was loaded from, else nil. Set by Loader.
    attr_accessor :file

    # name: see Names. desc: one line for the list in `metacrunch --help`.
    def initialize(name, desc: nil, &recipe)
      raise ArgumentError, "a command needs a block" unless recipe

      @name = Names.check!(name, "command")
      @desc = Names.check_desc!(desc)
      @recipe = recipe
    end

    # Evaluates the recipe. binder takes the Params schema and returns the
    # bound values. Raises ParamError for invalid arguments and
    # ArgumentError for a recipe without or with two run blocks.
    def prepare(binder:)
      builder = CommandBuilder.new(binder:)
      builder.instance_exec(&@recipe)
      builder.build
    end

    # The declared parameters. Evaluates the recipe only up to its first
    # statement, so the body never runs.
    def describe
      builder = CommandBuilder.new(binder: nil, describe: true)
      catch(RecipeParams::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
