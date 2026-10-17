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
    # credentials: -e and --credentials. progress: called with whether a
    # job's records go to stdout; returns a monitor for Engine or nil.
    def initialize(project: nil, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout,
                   environment: nil, credentials: nil, progress: nil)
      @project = project
      @logger = logger
      @env = env
      @stdin = stdin
      @stdout = stdout
      @environment = environment
      @credentials = credentials
      @progress = progress
      @status = :ok
    end

    # The project that names resolve in, or nil.
    def project
      @project = @project.call if @project.is_a?(Proc)
      @project
    end

    # The root of the project, a Pathname. Raises ProjectError without one.
    def root
      project&.root || raise(ProjectError, "no #{Project::FILE} found in #{Dir.pwd} or above")
    end

    # Runs target, a name or a path, with argv as on the command line, each
    # converted with to_s. Returns the Result of a job or transform, or a
    # command's value. Raises InvokeError if the target is unknown, argv is
    # invalid for it or the job aborted; exceptions from a command's body
    # pass unchanged.
    def invoke(target, *argv, workers: nil, limit: nil)
      target = target.to_s
      argv = arguments(target, argv)
      declaration, anchor = wrap(target) { resolve(target) }
      return invoke_job(declaration, argv, target:, anchor:, workers:, limit:) unless declaration.is_a?(Command)
      if workers || limit
        raise ArgumentError, "#{target} is a command; workers: and limit: apply to jobs and transforms"
      end

      invoke_command(declaration, argv, target:, anchor:)
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

    # The pipeline of a job or transform with argv bound: the command line,
    # env:, the credentials searched from anchor, then the default. The
    # transforms it uses resolve here and read the same credentials.
    def pipeline(job, argv, anchor:)
      credentials = credentials_for(anchor)
      context = UseContext.new(resolver: self, env: @env, credentials:, logger: @logger)
      job.pipeline(binder: binder(argv, credentials), logger: @logger, context:)
    end

    # Evaluates the command's recipe with argv bound as pipeline does.
    def prepare(command, argv, anchor:)
      command.prepare(binder: binder(argv, credentials_for(anchor)))
    end

    # Runs the body of a prepared command and returns its value.
    def call(prepared)
      CommandScope.new(params: prepared.params, logger: @logger, invoker: self).instance_exec(&prepared.body)
    end

    # Runs a job like `metacrunch run`: options are the run options (-i,
    # -o, ...); their defaults read stdin for a job without source and
    # write stdout for one without sink. Logs the job's error and its
    # summary, prefixed with label, and returns the Result.
    def run_job(job, argv, anchor:, options: RunOptions.new, workers: nil, label: nil)
      built = pipeline(job, argv, anchor:)
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

    # Arguments as on the command line. nil would bind an empty string, an
    # Array (a forgotten *) or a Hash its inspect; they raise instead.
    def arguments(target, argv)
      argv.each_with_index do |argument, index|
        problem = argument_problem(argument)
        raise ArgumentError, "invoke #{target}: argument #{index + 1} #{problem}" if problem
      end
      argv.map(&:to_s)
    end

    def argument_problem(argument)
      case argument
      when nil then "is nil"
      when Array then "is an Array; splat it with *"
      when Hash then "is a Hash; give the arguments as on the command line"
      end
    end

    # Project#fetch raises for a name declared more than once.
    def by_name(project, name, select)
      raise UsageError, "--job selects in a file; #{name} is a name" if select

      [project.fetch(name), project.file]
    end

    def by_path(path, select, kind, hint)
      declaration = Loader.load(path, name: select, kind:, hint:)
      [declaration, declaration.file]
    end

    def invoke_job(job, argv, target:, anchor:, workers:, limit:)
      result = wrap(target) do
        run_job(job, argv, anchor:, options: RunOptions.new(limit:), workers:, label: target)
      rescue NoInputError
        # invoke has no -i: the job reads the stdin of the chain.
        raise NoInputError, "pipe JSON Lines into the command that invokes it"
      end
      aborted!(result, target)
      result
    end

    def invoke_command(command, argv, target:, anchor:)
      call(wrap(target) { prepare(command, argv, anchor:) })
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

    def binder(argv, credentials)
      warn = ->(message) { @logger.warn(message) }
      ->(schema) { schema.bind_argv(argv, env: @env, credentials:, warn:) }
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
