# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch trace: shows what each step does to the first records. All
    # sinks are replaced by null sinks and no before/after hook runs, so a
    # trace changes nothing; failures are shown and skipped.
    class TraceCommand < JobCommand

      NAME = "trace"
      SUMMARY = "Show what each step does to the first records"
      USAGE = "trace [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]"
      DEFAULT_LIMIT = 10
      DEFAULT_WIDTH = 160

      def initialize(streams)
        super
        @full = false
      end

      private

      def define_options(parser)
        super
        parser.separator("")
        parser.on("-n", "--limit N", Integer, "Trace N records (default: #{DEFAULT_LIMIT})") do |count|
          raise UsageError, "--limit must be at least 1" unless count.positive?

          @limit = count
        end
        parser.on("--position LIST", Array, "Trace only these positions, e.g. 12,4711") do |list|
          @positions = list.map { position(it) }
        end
        parser.on("--id LIST", Array, "Trace only records with these ids") { @ids = it }
        parser.on("--full", "Show whole records instead of changes") { @full = true }
        parser.on("-i", "--input PATH", "Read JSON Lines from PATH (- for stdin) instead of the job's source") do |path|
          @input = path
        end
      end

      def execute_job(job, argv)
        raise UsageError, "use either --position or --id" if @positions && @ids

        pipeline = traced_pipeline(build_pipeline(job, argv))
        trace = Metacrunch::Trace.new(@stdout, pipeline:, positions: @positions, ids: @ids, full: @full,
                                               color: color?, width:)
        result = Engine.new(pipeline, observer: trace, select: trace.method(:trace?)).run
        trace.finish
        return EXIT_CODES[:ok] unless result.status == :aborted

        logger.error("#{result.error.class}: #{result.error.message}")
        EXIT_CODES[:aborted]
      end

      def traced_pipeline(pipeline)
        null = SinkAdapter.new(Metacrunch::Trace::NullSink.new)
        RunOptions.new(input: @input).apply_input(pipeline, stdin: @stdin).with(
          sink: null, rejects: null, errors: null, on_error: :skip, max_errors: nil, limit:,
          before_hooks: [], after_hooks: []
        )
      end

      def limit
        @limit || (@positions || @ids)&.size || DEFAULT_LIMIT
      end

      def position(text)
        value = Integer(text, 10, exception: false)
        raise UsageError, "--position needs positive numbers, got #{text}" unless value&.positive?

        value
      end

      def color?
        @stdout.tty? && @env.fetch("NO_COLOR", "").empty?
      end

      def width
        return DEFAULT_WIDTH unless @stdout.tty? && @stdout.respond_to?(:winsize)

        @stdout.winsize[1]
      rescue SystemCallError
        DEFAULT_WIDTH
      end

    end
  end
end
