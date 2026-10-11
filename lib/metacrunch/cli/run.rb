# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch run: runs a job. A job without source reads JSON Lines from
    # stdin, a job without sink writes them to stdout.
    class RunCommand < JobCommand

      NAME = "run"
      SUMMARY = "Run a job"
      USAGE = "run [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]"

      def initialize(streams)
        super
        @options = {}
      end

      private

      def define_options(parser)
        super
        parser.separator("")
        parser.on("-i", "--input PATH", "Read JSON Lines from PATH (- for stdin) instead of the job's source") do |path|
          @options[:input] = path
        end
        parser.on("-o", "--output PATH", "Write JSON Lines to PATH (- for stdout) instead of the job's sink") do |path|
          @options[:output] = path
        end
        parser.on("--rejects PATH", "Write rejected records with their context to PATH") { @options[:rejects] = it }
        parser.on("--errors PATH", "Write failed records with their context to PATH") { @options[:errors] = it }
        parser.on("-n", "--limit N", Integer, "Process only the first N source records") do |count|
          raise UsageError, "--limit must be at least 1" unless count.positive?

          @options[:limit] = count
        end
        parser.on("--on-error POLICY", "abort or skip, instead of the job's error policy") do |policy|
          raise UsageError, "--on-error must be abort or skip" unless ["abort", "skip"].include?(policy)

          @options[:on_error] = policy.to_sym
        end
        parser.on("--max-errors N", Integer, "Stop after more than N failed records (needs skip)") do |count|
          raise UsageError, "--max-errors must not be negative" if count.negative?

          @options[:max_errors] = count
        end
        parser.on("--stats PATH", "Write status and stats as JSON to PATH (- for stdout)") { @options[:stats] = it }
        parser.on("--[no-]progress", "Show progress on stderr (default: if stderr is a terminal)") { @progress = it }
      end

      def execute_job(job, argv)
        options = RunOptions.new(**@options)
        built = build_pipeline(job, argv)
        pipeline = options.apply(built, stdin: @stdin, stdout: @stdout)
        result = Engine.new(pipeline, monitor: progress(options.records_to_stdout?(built))).run
        code = report(result)
        write_stats(options.stats, result) if options.stats
        code
      end

      # A status line if stderr is a terminal, log lines with --progress
      # otherwise. Off by default with -q, and when records go to stdout on
      # the same terminal, where the line would mix with them.
      def progress(records_to_stdout)
        enabled = @progress
        enabled = default_progress?(records_to_stdout) if enabled.nil?
        return unless enabled

        Progress.new(log_output, mode: @stderr.tty? ? :line : :log, logger:)
      end

      def default_progress?(records_to_stdout)
        @stderr.tty? && @log_level < Logger::WARN && !(records_to_stdout && @stdout.tty?)
      end

      def log_output
        @log_output ||= Progress::Output.new(@stderr)
      end

      def write_stats(path, result)
        error = result.error && {"class" => result.error.class.name, "message" => result.error.message}
        json = JSON.pretty_generate({"status" => result.status, "error" => error, "stats" => result.stats.to_h})
        path == JsonLines::STDIO ? @stdout.puts(json) : File.write(path, "#{json}\n")
      end

      # Logs the error and its cause once each (a StepError message already
      # names its cause), then the status and stats.
      def report(result)
        error = result.error
        if error
          logger.error("#{error.class}: #{error.message}")
          cause = error.cause
          logger.error("caused by #{cause.class}: #{cause.message}") if cause && !error.is_a?(StepError)
        end
        logger.info("#{result.status}: #{result.stats.summary}")
        EXIT_CODES.fetch(result.status)
      end

    end
  end
end
