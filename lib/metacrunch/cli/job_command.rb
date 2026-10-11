# frozen_string_literal: true

module Metacrunch
  class Cli
    # A command that takes a job file (run, check, trace). Options before
    # JOB_FILE belong to the command, everything after it to the job.
    # Subclasses implement #execute_job(job, argv).
    class JobCommand < Command

      HELP_OPTIONS = ["-h", "--help"].freeze

      private

      def define_options(parser)
        parser.separator("Options go before JOB_FILE; everything after it belongs to the job.")
        parser.separator("\"metacrunch #{self.class::NAME} JOB_FILE --help\" shows the job's parameters.")
        parser.separator("")
        parser.on("-j", "--job NAME", "Select a job in a file that defines several") { @job_name = it }
        parser.on("-q", "--quiet", "Log warnings and errors only") { @log_level = Logger::WARN }
        parser.on("-v", "--verbose", "Log debug messages too") { @log_level = Logger::DEBUG }
        credentials_options(parser, "Credentials directory (default: METACRUNCH_CREDENTIALS,",
                            "then .metacrunch/ above the job file, then ~/.metacrunch/)")
      end

      def execute(argv)
        @job_file = argv.shift
        raise UsageError, "no job file given" unless @job_file

        job = Metacrunch.load_job(@job_file, name: @job_name)
        schema = requested_job_help(job, argv)
        return show(job_help(schema)) if schema

        execute_job(job, argv)
      end

      # Describes the job (evaluates its recipe up to params) only if -h or
      # --help appears before "--"; the job's own parser then decides, so -h
      # as the value of another option does not count.
      def requested_job_help(job, argv)
        return unless argv.take_while { it != "--" }.intersect?(HELP_OPTIONS)

        schema = job.describe
        schema if schema.help_requested?(argv)
      end

      def job_help(schema)
        args = schema.args_definition ? " #{schema.args_definition.name.to_s.upcase}..." : ""
        "Usage: metacrunch #{self.class::NAME} #{@job_file} [JOB_PARAMS...]#{args}\n\n#{schema.help}"
      end

      # Evaluates the recipe with the job's arguments. Credentials are read
      # only if a parameter needs them.
      def build_pipeline(job, argv)
        credentials = Credentials.store(job_file: job.file, env: @env, logger:, environment: @environment,
                                        directory: @credentials)
        warn = ->(message) { logger.warn(message) }
        job.pipeline(binder: ->(schema) { schema.bind_argv(argv, env: @env, credentials:, warn:) }, logger:)
      end

    end
  end
end
