# frozen_string_literal: true

module Metacrunch
  class Cli
    # A command that takes a job, transform or command by name or file
    # (run, check, trace). Options before it belong to the command,
    # everything after it to the target. Subclasses implement
    # #execute_job(job, argv), which also gets transforms; run also
    # #execute_command(command, argv).
    class JobCommand < Command

      HELP_OPTIONS = ["-h", "--help"].freeze

      private

      def define_options(parser)
        parser.separator("Options go before NAME|FILE; everything after it is passed on.")
        parser.separator("\"metacrunch #{self.class::NAME} NAME|FILE --help\" shows its parameters.")
        parser.separator("")
        parser.on("-j", "--job NAME", "Select a job, transform or command in a file that declares several") do |name|
          @job_name = name
        end
        parser.on("-q", "--quiet", "Log warnings and errors only") { @log_level = Logger::WARN }
        parser.on("-v", "--verbose", "Log debug messages too") { @log_level = Logger::DEBUG }
        credentials_options(parser, "Credentials directory (default: METACRUNCH_CREDENTIALS,",
                            "then .metacrunch/ above the Metacrunchfile for a name or above the file,",
                            "then ~/.metacrunch/)")
      end

      def execute(argv)
        @target = argv.shift
        raise UsageError, "no job, transform, command or file given" unless @target

        declaration, @anchor = invoker.resolve(@target, select: @job_name)
        check_target!(declaration)
        schema = requested_help(declaration, argv)
        return show(help_text(declaration, schema)) if schema
        return execute_command(declaration, argv) if declaration.is_a?(Metacrunch::Command)

        execute_job(declaration, argv)
      rescue NoInputError => e
        # Only the command line knows the target as the user named it.
        raise e.for(@target)
      end

      # check and trace take jobs and transforms, no commands; run overrides
      # this.
      def check_target!(declaration)
        return unless declaration.is_a?(Metacrunch::Command)

        raise UsageError, "#{@target} is a command; #{self.class::NAME} takes jobs and transforms"
      end

      # Describes the target (evaluates its recipe up to the first
      # statement) only if -h or --help appears before "--"; its own parser
      # then decides, so -h as the value of another option does not count.
      def requested_help(declaration, argv)
        return unless argv.take_while { it != "--" }.intersect?(HELP_OPTIONS)

        schema = declaration.describe(root: invoker.method(:root))
        schema if schema.help_requested?(argv)
      end

      def help_text(declaration, schema)
        params = declaration.is_a?(Metacrunch::Job) ? "[JOB_PARAMS...]" : "[PARAMS...]"
        args = schema.args_definition ? " #{schema.args_definition.name.to_s.upcase}..." : ""
        desc = declaration.desc ? "#{declaration.desc}\n\n" : ""
        "Usage: metacrunch #{self.class::NAME} #{@target} #{params}#{args}\n\n#{desc}#{schema.help}"
      end

      # Runs jobs, transforms and commands with this call's environment,
      # credentials options, logger and streams. Names resolve in the project
      # of the working directory, which is loaded when a name first needs it.
      def invoker
        @invoker ||= Invoker.new(
          project: -> { @lookup.project(logger) }, logger:, env: @env, stdin: @stdin, stdout: @stdout,
          environment: @environment, credentials: @credentials, progress: progress_factory
        )
      end

      # A callable that gets whether records go to stdout and returns a
      # progress display or nil; only run shows progress.
      def progress_factory = nil

      # Evaluates the recipe with the job's arguments. Credentials are read
      # only if a parameter needs them.
      def build_pipeline(job, argv) = invoker.pipeline(job, anchor: @anchor, argv:)

    end
  end
end
