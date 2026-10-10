# frozen_string_literal: true

require "optparse"
require_relative "../metacrunch"

module Metacrunch
  # Minimal command line interface. Sub-project 2 replaces it with
  # subcommands.
  class Cli

    USAGE = "Usage: metacrunch [-h|-v] JOB_FILE [--job NAME] [JOB_PARAMS...] [ARGS...]"
    EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3, interrupted: 130}.freeze
    HELP_OPTIONS = ["-h", "--help"].freeze

    def initialize(stdout: $stdout, stderr: $stderr, env: ENV)
      @stdout = stdout
      @stderr = stderr
      @env = env
      @logger = Metacrunch.build_logger(stderr)
    end

    # Runs the CLI and returns the exit code.
    def run(argv)
      argv = argv.dup
      action, parser = global_action(argv)
      return show(parser.help) if action == :help
      return show(VERSION) if action == :version

      run_job(argv)
    rescue OptionParser::ParseError, JobLoadError, ParamError => e
      usage_error(e.message)
    rescue SignalException => e
      # Ctrl-C (SIGINT) or SIGTERM. Exit code 128 + signal number, as shells
      # report it; exe/metacrunch then ends by the signal itself.
      @logger.warn("interrupted by SIG#{Signal.signame(e.signo)}")
      128 + e.signo
    rescue *Engine::RECOVERABLE => e
      @logger.error(e.full_message(highlight: false))
      EXIT_CODES[:aborted]
    end

    private

    def run_job(argv)
      job_file = argv.shift
      return usage_error("no job file given") unless job_file

      job = Metacrunch.load_job(job_file, name: extract_job_name(argv))
      if help_mentioned?(argv)
        schema = job.describe
        return show(job_help(job_file, schema)) if schema.help_requested?(argv)
      end

      report(job.run(argv, env: @env, logger: @logger))
    end

    # Parses the options before JOB_FILE. Returns [action, parser].
    def global_action(argv)
      action = nil
      parser = OptionParser.new(USAGE) do |opts|
        opts.on("-h", "--help", "Show this help") { action = :help }
        opts.on("-v", "--version", "Show the version") { action = :version }
      end
      parser.order!(argv)
      [action, parser]
    end

    # Removes --job NAME or --job=NAME from argv and returns NAME.
    def extract_job_name(argv)
      index = options_part(argv).index { |arg| arg == "--job" || arg.start_with?("--job=") }
      return unless index

      option = argv.delete_at(index)
      return option.delete_prefix("--job=") if option.start_with?("--job=")

      argv.delete_at(index) || raise(ParamError, "--job needs a job name")
    end

    # A quick check before the job's parser decides: only then is the job
    # described (which evaluates the start of its recipe).
    def help_mentioned?(argv)
      options_part(argv).intersect?(HELP_OPTIONS)
    end

    # The arguments before a "--" separator.
    def options_part(argv)
      argv.take_while { |arg| arg != "--" }
    end

    def job_help(job_file, schema)
      args = schema.args_definition ? " #{schema.args_definition.name.to_s.upcase}..." : ""
      "Usage: metacrunch #{job_file} [JOB_PARAMS...]#{args}\n\n#{schema.help}"
    end

    # Logs the error and its cause once each (a StepError message already
    # names its cause), then the status and stats.
    def report(result)
      error = result.error
      if error
        @logger.error("#{error.class}: #{error.message}")
        cause = error.cause
        @logger.error("caused by #{cause.class}: #{cause.message}") if cause && !error.is_a?(StepError)
      end
      @logger.info("#{result.status}: #{result.stats.summary}")
      EXIT_CODES.fetch(result.status)
    end

    def show(text)
      @stdout.puts(text)
      EXIT_CODES[:ok]
    end

    def usage_error(message)
      @stderr.puts("Error: #{message}", USAGE)
      EXIT_CODES[:usage]
    end

  end
end
