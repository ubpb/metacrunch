# frozen_string_literal: true

require_relative "../metacrunch"

module Metacrunch
  # Runs jobs in tests without I/O: all sinks are replaced by in-memory
  # sinks, and the source can be replaced by any Enumerable.
  module Testing

    # Keeps records and their contexts.
    class MemorySink

      attr_reader :records, :contexts

      def initialize
        @records = []
        @contexts = []
      end

      def write(record, ctx)
        @records << record
        @contexts << ctx
      end

    end

    # Collects the records of jobs without a sink. Reports nothing as
    # delivered, so the run's stats show written: 0, as in a real run.
    class UncountedSinkAdapter < SinkAdapter

      def delivered = 0

    end

    # records: what reached the sink. rejects: [record, Rejection] pairs.
    # errors: [record, Failure] pairs.
    Result = Data.define(:records, :rejects, :errors, :stats, :status, :error) do
      def ok? = status == :ok
    end

    # One invoke recorded by Testing.invoke. params: as given. options:
    # workers: and limit: as given.
    Invocation = Data.define(:name, :params, :options)

    # value: what the body returned. status: :ok, :ok_with_failures (an
    # invoked job ended with failed records, or aborted and the body went
    # on) or :aborted (an exception left the body; error holds it).
    CommandResult = Data.define(:value, :status, :error, :invoked) do
      def ok? = status == :ok
    end

    # A stub that gives no valid answer. Testing.invoke raises it instead
    # of ending the run :aborted, so a mistake in a test's stubs is never
    # taken for a failing command.
    class StubError < ArgumentError; end

    EMPTY_STATS = Stats.new(read: 0, written: 0, filtered: 0, rejected: {}, marked: {}, failed: {}, steps: {},
                            duration: 0.0)

    # Records invokes instead of running them and answers from stubs: a
    # status Symbol or a Result for a job, a value or a
    # Metacrunch::CommandResult for a command, or a callable that gets the
    # params Hash and returns one of these. Without a stub a job ends :ok
    # and a command returns nil. Names resolve as in a real run, so unknown
    # names raise InvokeError.
    class RecordingInvoker < Invoker

      attr_reader :invoked

      def initialize(project:, stubs:, logger:)
        super(project:, logger:, env: {}, stdin: nil, stdout: nil)
        @stubs = stubs.transform_keys(&:to_s)
        @invoked = []
      end

      private

      # ** takes the anchor:, which a recording needs no more than the
      # declaration itself.
      def invoke_job(_job, params, target:, workers:, limit:, **)
        @invoked << Invocation.new(name: target, params:, options: {workers:, limit:}.compact)
        result = job_result(target, answer(target, params, :ok))
        track(result.status)
        aborted!(result, target)
        result
      end

      def invoke_command(_command, params, target:, **)
        @invoked << Invocation.new(name: target, params:, options: {})
        command_stub_result(target, answer(target, params, nil))
      end

      # A value is what the stubbed body returned; a CommandResult also
      # gives the status, which counts toward the command under test.
      def command_stub_result(target, stub)
        unless stub.is_a?(Metacrunch::CommandResult)
          return Metacrunch::CommandResult.new(status: :ok, error: nil, value: stub)
        end
        unless [:ok, :ok_with_failures].include?(stub.status)
          raise StubError, "the stub for #{target} must give a CommandResult with status :ok or :ok_with_failures, " \
                           "got #{stub.status.inspect}"
        end

        track(stub.status)
        stub
      end

      def answer(target, params, default)
        stub = @stubs.fetch(target, default)
        stub.respond_to?(:call) ? stub.call(params) : stub
      end

      def job_result(target, stub)
        case stub
        when Metacrunch::Result then stub
        when *STATUSES
          error = stub == :aborted ? RuntimeError.new("stubbed abort") : nil
          Metacrunch::Result.new(status: stub, error:, stats: EMPTY_STATS)
        else
          raise StubError, "the stub for #{target} must give a status Symbol or a Result, got #{stub.inspect}"
        end
      end

    end

    module_function

    # Runs a job or transform without I/O: target is a Project with the
    # name of one of its jobs or transforms, or a Job or Transform, whose
    # names resolve in project:, else in the project of the working
    # directory (see UseContext.for). params are bound like the values of
    # `use` (see Params#bind_values), with an empty environment and no
    # credentials; the transforms of the job get neither either. The job's
    # sinks are built but never opened. Records are collected even if the
    # job has no sink; stats.written is 0 then, as in a real run. workers:
    # run the steps in that many processes, to check that the job's records
    # cross process boundaries. A transform needs source:.
    def run(target, name = nil, params: {}, source: nil, logger: Logger.new(nil), workers: nil, project: nil)
      job, project = run_target(target, name, project)
      unless source.nil? || source.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{source.inspect}"
      end

      context = UseContext.for(project:, env: {}, credentials: nil, logger:)
      pipeline = job.pipeline(binder: values_binder(params), logger:, context:)
      memory = {sink: MemorySink.new, rejects: MemorySink.new, errors: MemorySink.new}
      adapters = memory.transform_values { |sink| SinkAdapter.new(sink) }
      adapters[:sink] = UncountedSinkAdapter.new(memory[:sink]) unless pipeline.sink
      source ||= pipeline.source
      unless source
        raise ArgumentError, "#{job.is_a?(Transform) ? "a transform" : "the job"} has no source; pass source:"
      end

      pipeline = pipeline.with(source:, **adapters)
      result = Engine.new(pipeline, executor: Executor.for(workers)).run
      Result.new(
        records: memory[:sink].records,
        rejects: memory[:rejects].records.zip(memory[:rejects].contexts.map(&:rejection)),
        errors: memory[:errors].records.zip(memory[:errors].contexts.map(&:failure)),
        stats: result.stats,
        status: result.status,
        error: result.error
      )
    end

    # Runs the body of a command with params bound as run does (no
    # environment, no credentials): the command name of project, or a
    # Command (from Metacrunch.load_command, say), whose names resolve in
    # project:, else in the project of the working directory, loaded when a
    # name is first needed. Every invoke in the body is recorded and
    # answered from stubs (name => status Symbol, Result, value, or callable
    # that gets the params) instead of run; see RecordingInvoker. A stub for
    # a name that does not resolve raises ArgumentError, as does a job name
    # for name; a job's stub without a status raises StubError (an
    # ArgumentError).
    def invoke(target, name = nil, params: {}, stubs: {}, logger: Logger.new(nil), project: nil)
      command, project = invoke_target(target, name, project)
      invoker = RecordingInvoker.new(project:, stubs:, logger:)
      unknown = stubs.keys.map(&:to_s).reject { File.file?(it) || invoker.project&.include?(it) }
      raise ArgumentError, "stub for unknown job, transform or command: #{unknown.first}" if unknown.any?

      run_command(invoker, command.prepare(binder: values_binder(params), root: invoker.method(:root)))
    end

    # Binds params like the values of `use`, but tests read neither the
    # environment nor credentials.
    def values_binder(params) = ->(schema) { schema.bind_values(params, env: {}, credentials: nil) }
    private_class_method :values_binder

    # [job or transform, project] for run.
    def run_target(target, name, project)
      case target
      when Project
        raise ArgumentError, "project: is for a job or transform; the first argument is a project already" if project
        raise ArgumentError, "the name of a job or transform is missing" unless name

        declaration = target.fetch(name)
        raise ArgumentError, "#{name} is a command; test it with Testing.invoke" if declaration.is_a?(Command)

        [declaration, target]
      when Job, Transform
        raise ArgumentError, "a job or transform needs no name, got #{name.inspect}" if name

        [target, project]
      else
        raise ArgumentError, "Testing.run takes a project and the name of a job or transform, or a job or " \
                             "transform; got #{target.inspect}"
      end
    end
    private_class_method :run_target

    # [command, project] for invoke; project may be a Proc.
    def invoke_target(target, name, project)
      case target
      when Project then [project_command(target, name, project), target]
      when Command
        raise ArgumentError, "a command needs no name, got #{name.inspect}" if name
        unless project.nil? || project.is_a?(Project)
          raise ArgumentError, "project: must be a Metacrunch::Project, got #{project.inspect}"
        end

        [target, project || -> { Project.nearest }]
      else
        raise ArgumentError, "Testing.invoke takes a project and the name of a command, or a command; " \
                             "got #{target.inspect}"
      end
    end
    private_class_method :invoke_target

    def project_command(project, name, other)
      raise ArgumentError, "project: is for a command; the first argument is a project already" if other
      raise ArgumentError, "the name of a command is missing" unless name

      command = project.fetch(name)
      unless command.is_a?(Command)
        raise ArgumentError, "#{name} is a #{Loader::KINDS.fetch(command.class)}; test it with Testing.run"
      end

      command
    end
    private_class_method :project_command

    def run_command(invoker, prepared)
      value = invoker.call(prepared)
      CommandResult.new(value:, status: invoker.finished_status, error: nil, invoked: invoker.invoked)
    rescue StubError
      raise
    rescue *Engine::RECOVERABLE => e
      CommandResult.new(value: nil, status: :aborted, error: e, invoked: invoker.invoked)
    end
    private_class_method :run_command

  end
end
