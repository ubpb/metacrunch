# frozen_string_literal: true

module Metacrunch
  # Runs jobs, transforms and commands with the context of one call: the
  # environment, the credentials options (-e, --credentials), the logger,
  # stdin and stdout, and the progress display. The CLI runs its target
  # through it, and a command's body invokes through it, so a whole chain
  # shares that context. It also resolves the names of `use` (see
  # UseContext). Tracks the worst status of the jobs it ran.
  class Invoker

    STATUSES = [:ok, :ok_with_failures, :aborted].freeze
    # Errors that mean the invoking command passed a wrong target or wrong
    # arguments; invoke raises them as InvokeError.
    WRAPPED = [ParamError, UsageError, JobLoadError, ProjectError].freeze

    attr_reader :logger, :status

    # project: the Project that names resolve in, nil, or a Proc that
    # returns one of these when a name is first needed. environment and
    # credentials: -e and --credentials. params_file: --params, the path of
    # a ParamsFile for the parameters bound from the command line only.
    # progress: called with whether a job's records go to stdout; returns a
    # monitor for Engine or nil.
    def initialize(project: nil, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout,
                   environment: nil, credentials: nil, params_file: nil, progress: nil)
      @project = project
      @logger = logger
      @env = env
      @stdin = stdin
      @stdout = stdout
      @environment = environment
      @credentials = credentials
      @params_file = params_file
      @progress = progress
      @status = :ok
    end

    # The project that names resolve in, or nil.
    def project
      @project = @project.call if @project.is_a?(Proc)
      @project
    end

    # The root of the project, a Pathname. While the project is a Proc
    # (loaded when a name first needs it), the nearest Metacrunchfile above
    # the working directory is found without loading it, once per call: a
    # step may ask for every record. Raises ProjectError without one.
    def root
      return @project.root if @project.is_a?(Project)

      @root ||= begin
        file = Project.find(Dir.pwd) if @project.is_a?(Proc)
        raise ProjectError, "no #{Project::FILE} found in #{Dir.pwd} or above" unless file

        Pathname(File.dirname(file))
      end
    end

    # Runs target, a name or a path, with params bound by name (see
    # Params#bind_values). Returns the Result of a job or transform, or the
    # CommandResult of a command. Raises InvokeError if the target is
    # unknown, params are invalid for it or the job aborted, and
    # ArgumentError if params is no Hash; exceptions from a command's body
    # pass unchanged.
    def invoke(target, params: {}, workers: nil, limit: nil, secrets: [])
      target = target.to_s
      raise ArgumentError, "invoke #{target}: params: must be a Hash, got #{params.inspect}" unless params.is_a?(Hash)

      declaration, anchor = wrap(target) { resolve(target) }
      unless declaration.is_a?(Command)
        return invoke_job(declaration, params, target:, anchor:, workers:, limit:, secrets:)
      end
      if workers || limit
        raise ArgumentError, "#{target} is a command; workers: and limit: apply to jobs and transforms"
      end

      invoke_command(declaration, params, target:, anchor:, secrets:)
    end

    # [declaration, anchor] for target. A target with / or . is a path; any
    # other is a name of the project, else an existing file of that name.
    # anchor is the file credentials are searched from: the Metacrunchfile
    # for a name, the file itself for a path. select: -j, for paths only.
    # kind: what a path may give (Transform for use) and hint: how to pick
    # one of several, as for Loader.load.
    def resolve(target, select: nil, kind: nil, hint: Loader::SELECT_HINT)
      return by_path(target, select, kind, hint) if Names.path?(target)

      current = project
      return by_name(current, target, select) if current&.include?(target)
      return by_path(target, select, kind, hint) if File.file?(target)

      hint = current ? current.load_hint : " (no #{Project::FILE} found)"
      raise ProjectError, "unknown job, transform, command or file: #{target}#{hint}"
    end

    # The pipeline of a job or transform with its parameters bound from
    # argv (the command line) or params (code): then env:, the credentials
    # searched from anchor, then the default. The transforms it uses
    # resolve here and read the same credentials.
    def pipeline(job, anchor:, argv: nil, params: nil, secrets: [], target: nil)
      credentials = credentials_for(anchor)
      context = UseContext.new(resolver: self, env: @env, credentials:, logger: @logger)
      job.pipeline(binder: binder(credentials, argv:, params:, secrets:, target:), logger: @logger, context:)
    end

    # Evaluates the command's recipe with argv or params bound as pipeline
    # does.
    def prepare(command, anchor:, argv: nil, params: nil, secrets: [], target: nil)
      command.prepare(binder: binder(credentials_for(anchor), argv:, params:, secrets:, target:), root: method(:root))
    end

    # Runs the body of a prepared command and returns its value.
    def call(prepared)
      CommandScope.new(params: prepared.params, logger: @logger, invoker: self).instance_exec(&prepared.body)
    end

    # Runs a job like `metacrunch run`: options are the run options (-i,
    # -o, ...); their defaults read stdin for a job without source and
    # write stdout for one without sink. Logs the job's error and its
    # summary, prefixed with label, and returns the Result.
    def run_job(job, anchor:, argv: nil, params: nil, options: RunOptions.new, workers: nil, label: nil, secrets: [])
      built = pipeline(job, anchor:, argv:, params:, secrets:, target: label)
      pipeline = options.apply(built, stdin: @stdin, stdout: @stdout)
      monitor = @progress&.call(options.records_to_stdout?(built))
      result = Engine.new(pipeline, executor: Executor.for(workers), monitor:).run
      report(result, label)
      track(result.status)
      result
    end

    # The status of a command whose body finished: :ok, or
    # :ok_with_failures if a job it invoked ended with failed records, or
    # aborted and the body went on.
    def finished_status = @status == :ok ? :ok : :ok_with_failures

    private

    # Project#fetch raises for a name declared more than once.
    def by_name(project, name, select)
      raise UsageError, "--job selects in a file; #{name} is a name" if select

      [project.fetch(name), project.file]
    end

    def by_path(path, select, kind, hint)
      declaration = Loader.load(path, name: select, kind:, hint:)
      [declaration, declaration.file]
    end

    def invoke_job(job, params, target:, anchor:, workers:, limit:, secrets:)
      result = wrap(target) do
        run_job(job, anchor:, params:, options: RunOptions.new(limit:), workers:, label: target, secrets:)
      rescue NoInputError
        # invoke has no -i: the job reads the stdin of the chain.
        raise NoInputError.new(target, hint: "pipe them into the command that invokes it")
      end
      aborted!(result, target)
      result
    end

    def invoke_command(command, params, target:, anchor:, secrets:)
      prepared = wrap(target) { prepare(command, anchor:, params:, secrets:, target:) }
      command_result { call(prepared) }
    end

    # Runs the block, the body of an invoked command, with a status of its
    # own: the worst status of the jobs run meanwhile, nested commands
    # included. The status of the chain keeps them too, also when the block
    # raises.
    def command_result
      outer = @status
      @status = :ok
      value = yield
      CommandResult.new(status: finished_status, error: nil, value:)
    ensure
      track(outer)
    end

    # The job has logged its error already.
    def aborted!(result, target)
      return unless result.status == :aborted

      error = result.error
      raise InvokeError.new("#{target} aborted: #{error.class}: #{error.message}", name: target, result:),
            cause: error
    end

    def wrap(target)
      yield
    rescue *WRAPPED => e
      raise InvokeError.new("invoke #{target}: #{e.message}", name: target)
    end

    # Read only if a parameter needs a value from them.
    def credentials_for(anchor)
      Credentials.store(job_file: anchor, env: @env, logger: @logger, environment: @environment,
                        directory: @credentials)
    end

    # argv: the command line, with a warning for a secret given there, and
    # the params file. params: values from code (see Params#bind_values).
    def binder(credentials, argv:, params:, secrets: [], target: nil)
      return ->(schema) { bind_params(schema, params, credentials, secrets, target) } if params

      warn = ->(message) { @logger.warn(message) }
      ->(schema) { bind_argv(schema, argv, credentials, warn) }
    end

    # Reads the params file for each binding, so a check sees it as the run
    # will, and logs the sections it took values from.
    def bind_argv(schema, argv, credentials, warn)
      return schema.bind_argv(argv, env: @env, credentials:, warn:) unless @params_file

      file = ParamsFile.load(@params_file)
      environment = Credentials.environment(@environment, @env)
      values = schema.bind_argv(argv, env: @env, credentials:, warn:, file:, environment:)
      @logger.debug("params: #{file.path} (#{file.select(environment).sections.join(", ")})")
      values
    end

    # An unknown key is a wrong argument of invoke, as an invalid value is:
    # both become a ParamError, which invoke raises as InvokeError.
    def bind_params(schema, params, credentials, secrets, target)
      schema.bind_values(params, env: @env, credentials:, secrets:, target:)
    rescue ArgumentError => e
      raise ParamError, e.message, cause: nil
    end

    # Logs the error and its cause once each (a StepError message already
    # names its cause), then the status and stats.
    def report(result, label)
      prefix = label ? "#{label}: " : ""
      error = result.error
      if error
        @logger.error("#{prefix}#{error.class}: #{error.message}")
        cause = error.cause
        @logger.error("#{prefix}caused by #{cause.class}: #{cause.message}") if cause && !error.is_a?(StepError)
      end
      @logger.info("#{prefix}#{result.status}: #{result.stats.summary}")
    end

    def track(status)
      @status = [@status, status].max_by { STATUSES.index(it) }
    end

  end
end
