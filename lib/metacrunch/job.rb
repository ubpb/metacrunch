# frozen_string_literal: true

module Metacrunch
  # A job is a recipe: a block in the DSL. It builds a fresh Pipeline for
  # every run, so loading a job has no side effects.
  class Job

    attr_reader :name, :desc

    # The file the job was loaded from (Metacrunch.load_job), else nil.
    # Credentials are searched from there.
    attr_accessor :file

    # name: see Names; nil for a job that runs by path only. desc: one line
    # for the list in `metacrunch --help`.
    def initialize(name = nil, desc: nil, &recipe)
      raise ArgumentError, "a job needs a block" unless recipe

      @name = name.nil? ? nil : Names.check!(name, "job")
      @desc = Names.check_desc!(desc)
      @recipe = recipe
    end

    # Evaluates the recipe. binder takes the Params schema and returns the
    # bound values. context: the UseContext that `use` resolves transforms
    # in; a recipe with `use` needs one.
    def pipeline(binder:, logger: Metacrunch.logger, context: nil)
      builder = Builder.new(binder:, logger:, context:)
      builder.instance_exec(&@recipe)
      builder.build
    end

    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments (CredentialsError, a ParamError, for unreadable credentials)
    # and lets errors from the recipe itself (e.g. a component constructor
    # or a DSL mistake) propagate. Errors while the pipeline runs end up in
    # the Result. limit stops after that many records; workers runs the
    # steps in that many processes. Credentials follow env:
    # METACRUNCH_ENV, METACRUNCH_CREDENTIALS, METACRUNCH_MASTER_KEY, HOME.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil, limit: nil, workers: nil)
      credentials = Credentials.store(job_file: file, env:, logger:)
      warn = ->(message) { logger.warn(message) }
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:, credentials:, warn:) }, logger:)
      Engine.new(built.with(limit:), observer:, executor: Executor.for(workers)).run
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
