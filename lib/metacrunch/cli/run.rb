# frozen_string_literal: true

require "etc"

module Metacrunch
  class Cli
    # metacrunch run: runs a job or a command. A job without source reads
    # JSON Lines from stdin, a job without sink writes them to stdout.
    class RunCommand < JobCommand

      NAME = "run"
      SUMMARY = "Run a job, transform or command"
      USAGE = "run [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]"
      # The options that apply to jobs and transforms only, as the usage
      # error names them; -w is kept apart in @workers.
      JOB_OPTIONS = {input: "-i", output: "-o", rejects: "--rejects", failures: "--failures", limit: "-n",
                     on_failure: "--on-failure", max_failures: "--max-failures", stats: "--stats"}.freeze

      def initialize(streams, lookup)
        super
        @options = {}
      end

      private

      def define_options(parser)
        super
        parser.on("--[no-]progress", "Show progress on stderr (default: if stderr is a terminal)") { @progress = it }
        parser.separator("")
        parser.separator("For jobs and transforms only:")
        parser.on("-i", "--input PATH", "Read JSON Lines from PATH (- for stdin) instead of the job's source") do |path|
          @options[:input] = path
        end
        parser.on("-o", "--output PATH", "Write JSON Lines to PATH (- for stdout) instead of the job's sink") do |path|
          @options[:output] = path
        end
        parser.on("--rejects PATH", "Write rejected records with their context to PATH") { @options[:rejects] = it }
        parser.on("--failures PATH", "Write failed records with their context to PATH") { @options[:failures] = it }
        parser.on("-n", "--limit N", Integer, "Process only the first N source records") do |count|
          raise UsageError, "--limit must be at least 1" unless count.positive?

          @options[:limit] = count
        end
        parser.on("--on-failure POLICY", "abort or skip, instead of the job's failure policy") do |policy|
          raise UsageError, "--on-failure must be abort or skip" unless ["abort", "skip"].include?(policy)

          @options[:on_failure] = policy.to_sym
        end
        parser.on("--max-failures N", Integer, "Stop after more than N failed records (needs skip)") do |count|
          raise UsageError, "--max-failures must not be negative" if count.negative?

          @options[:max_failures] = count
        end
        parser.on("-w", "--workers N", "Run the steps in N processes; auto: one per core but one") do |value|
          @workers = worker_count(value)
        end
        parser.on("--stats PATH", "Write status and stats as JSON to PATH (- for stdout)") { @options[:stats] = it }
      end

      def check_target!(declaration)
        return unless declaration.is_a?(Metacrunch::Command)

        given = @options.keys.map { JOB_OPTIONS.fetch(it) }
        given << "-w" if @workers
        raise UsageError, "#{@target} is a command; #{given.first} applies to jobs and transforms" if given.any?
      end

      def execute_job(job, argv)
        options = RunOptions.new(**@options)
        result = invoker.run_job(job, anchor: @anchor, argv:, options:, workers: @workers)
        write_stats(options.stats, result) if options.stats
        exit_code(result)
      end

      # A ProjectError that ended the run, such as root without a project
      # in a hook, is a usage error like any other project error.
      def exit_code(result)
        result.error.is_a?(ProjectError) ? EXIT_CODES[:usage] : EXIT_CODES.fetch(result.status)
      end

      # Invalid parameters of the command itself raise ParamError here, which
      # Command#run turns into exit status 2. Then the body runs.
      def execute_command(command, argv)
        finish(invoker.prepare(command, anchor: @anchor, argv:))
      end

      # 0, or 3 if an invoked job ended with failed records, or aborted and
      # the body went on; 1 if an exception left the body. An InvokeError is
      # logged as its message, since the job logged its error already.
      # Signals pass on to Command#run.
      def finish(prepared)
        invoker.call(prepared)
        EXIT_CODES.fetch(invoker.finished_status)
      rescue InvokeError => e
        logger.error(e.message)
        EXIT_CODES[:aborted]
      rescue *Engine::RECOVERABLE => e
        logger.error(e.full_message(highlight: false))
        EXIT_CODES[:aborted]
      end

      def progress_factory = method(:progress)

      # The value of --workers as a number of processes.
      def worker_count(value)
        count = value == "auto" ? Executor.auto_workers : Integer(value, 10, exception: false)
        raise UsageError, "--workers must be a positive number or auto" unless count&.positive?
        if count > 1 && !Executor::Fork.supported?
          raise UsageError, "--workers needs Process.fork, which this platform lacks"
        end

        count
      end

      # A status line if stderr is a terminal, log lines with --progress
      # otherwise. Off by default with -q, and when records go to stdout on
      # the same terminal, where the line would mix with them.
      def progress(records_to_stdout)
        enabled = @progress
        enabled = default_progress?(records_to_stdout) if enabled.nil?
        return unless enabled

        Progress.new(log_output, mode: @stderr.tty? ? :line : :log)
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

    end
  end
end
