# frozen_string_literal: true

module Metacrunch
  # A job is a recipe: a block in the DSL. It builds a fresh Pipeline for
  # every run, so loading a job has no side effects.
  class Job

    attr_reader :name

    def initialize(name = nil, &recipe)
      raise ArgumentError, "a job needs a block" unless recipe

      @name = name&.to_s
      @recipe = recipe
    end

    # Evaluates the recipe. binder takes the Params schema and returns the
    # bound values.
    def pipeline(binder:, logger: Metacrunch.logger)
      builder = Builder.new(binder:, logger:)
      builder.instance_exec(&@recipe)
      builder.build
    end

    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments and lets errors from the recipe itself (e.g. a component
    # constructor or a DSL mistake) propagate. Errors while the pipeline
    # runs end up in the Result.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil)
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:) }, logger:)
      Engine.new(built, observer:).run
    end

    # The declared parameters. Builds no source, step or sink.
    def describe
      builder = Builder.new(binder: nil, logger: Metacrunch.logger, describe: true)
      catch(Builder::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
