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

    # Runs the job with params bound by name (see Params#bind_values):
    # given values, then the defaults (references read env: and the credentials).
    # Raises ArgumentError for an unknown key and ParamError for invalid
    # values (CredentialsError, a ParamError, for unreadable credentials);
    # errors from the recipe itself (a component constructor, a DSL
    # mistake) propagate. Errors while the pipeline runs end up in the
    # Result. limit stops after that many records; workers runs the steps in
    # that many processes. environment: the environment of the credentials
    # (else METACRUNCH_ENV of env:); credentials also follow env:
    # METACRUNCH_CREDENTIALS, METACRUNCH_MASTER_KEY, HOME. project: where the
    # names of `use` resolve; without it, the project of the nearest
    # Metacrunchfile above Dir.pwd, loaded when a name needs it.
    def run(params: {}, env: ENV, environment: nil, logger: Metacrunch.logger, observer: nil, limit: nil, workers: nil,
            project: nil)
      credentials = Credentials.store(job_file: file, env:, logger:, environment:)
      context = UseContext.for(project:, env:, credentials:, logger:)
      built = pipeline(binder: ->(schema) { schema.bind_values(params, env:, credentials:) }, logger:, context:)
      Engine.new(built.with(limit:), observer:, executor: Executor.for(workers)).run
    end

    # The declared parameters. Builds no source, step or sink. root: the
    # root callable for defaults (see RecipeParams#root).
    def describe(root: nil)
      builder = Builder.new(binder: nil, logger: Metacrunch.logger, describe: true, root:)
      catch(Builder::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
