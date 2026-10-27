# frozen_string_literal: true

module Metacrunch
  # What `use` needs from the call that builds a job: a resolver for names
  # and paths (an Invoker), the environment and the credentials store the
  # job is bound with, and the logger. Nested transforms share it, so one
  # run reads one credentials file.
  class UseContext

    # How to pick one of several transforms in a file given by path.
    PATH_HINT = "use one by its name in a project, or as an object"
    # Where a Proc given to use belongs (see Params#use).
    GROUP_HINT = "a group of parameters goes into params { use ... }"

    # resolver: responds to resolve(target, kind:, hint:) and returns
    # [declaration, anchor], as Invoker#resolve does. credentials: a
    # Credentials::Store, or nil for none (tests).
    def initialize(resolver:, env:, credentials:, logger:)
      @resolver = resolver
      @env = env
      @credentials = credentials
      @logger = logger
    end

    # A context whose names resolve in project, or, without one, in the
    # project of the nearest Metacrunchfile above the working directory,
    # loaded when the first name needs it (Job#run, Testing.run). That
    # lookup loads the Metacrunchfile again for every call; callers that
    # run many jobs pass project: to load it once.
    def self.for(project:, env:, credentials:, logger:)
      unless project.nil? || project.is_a?(Project)
        raise ArgumentError, "project: must be a Metacrunch::Project, got #{project.inspect}"
      end

      resolver = Invoker.new(project: project || -> { Project.nearest }, logger:, env: env || {})
      new(resolver:, env:, credentials:, logger:)
    end

    # The Transform that target stands for: a Transform, or its name or
    # path (a String or Pathname). Raises ArgumentError for a job, a command
    # or any other object, ProjectError for an unknown name and
    # JobLoadError for a path without a transform.
    def transform(target)
      target = target.to_path if target.respond_to?(:to_path)
      declaration = declaration_for(target)
      return declaration if declaration.is_a?(Transform)

      name = declaration.name || (target if target.is_a?(String)) || "the target"
      raise ArgumentError, "use takes transforms; #{name} is a #{Loader::KINDS.fetch(declaration.class)}"
    end

    # The root of the project the job is built in (see Invoker#root).
    def root = @resolver.root

    # Evaluates the recipe of transform with params bound (see
    # Params#bind_values) and returns its pipeline: steps and hooks, no
    # source and no sinks. stack: the transforms whose recipes are being
    # evaluated around this use. Errors of the params name the transform,
    # after the transforms around it: "use outer → inner: ...". secrets:
    # the secret values of the job or transform that uses it (see
    # Params.secret_values).
    def evaluate(transform, params, stack:, secrets: [])
      chain = [*stack, transform].map(&:label).join(" → ")
      raise ArgumentError, "use cycle: #{chain}" if stack.include?(transform)

      binder = binder(chain, params, secrets, transform.label)
      transform.pipeline(binder:, logger: @logger, context: self, stack:)
    end

    private

    def declaration_for(target)
      return target if [Transform, Job, Command].any? { target.is_a?(it) }
      return @resolver.resolve(target, kind: Transform, hint: PATH_HINT).first if target.is_a?(String)

      got = target.is_a?(Proc) ? "a Proc; #{GROUP_HINT}" : target.inspect
      raise ArgumentError, "use takes a transform, its name or its path, got #{got}"
    end

    # No cause: the original message is part of the new one.
    def binder(chain, params, secrets, target)
      lambda do |schema|
        schema.bind_values(params, env: @env, credentials: @credentials, secrets:, target:)
      rescue ParamError, ArgumentError => e
        raise e.class, "use #{chain}: #{e.message}", cause: nil
      end
    end

  end
end
