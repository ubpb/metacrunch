# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch check: loads the job or transform, binds its parameters and
    # builds the pipeline; for a command, binds its parameters and prepares
    # it. Opens nothing, reads no record, runs no hook and no command body.
    # Parameter values are not printed; they may contain secrets.
    class CheckCommand < JobCommand

      NAME = "check"
      SUMMARY = "Validate a job, transform or command without running it"
      USAGE = "check [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]"

      private

      def check_target!(_declaration) = nil

      def execute_command(command, argv)
        invoker.prepare(command, anchor: @anchor, argv:)
        @stdout.puts("#{@target}: command #{command.name.inspect} OK")
        EXIT_CODES[:ok]
      end

      def execute_job(job, argv)
        pipeline = build_pipeline(job, argv)
        @stdout.puts(description(job, pipeline))
        EXIT_CODES[:ok]
      rescue *Engine::RECOVERABLE => e
        raise if e.is_a?(ParamError)

        @stderr.puts("Error: #{@target}: #{e.class}: #{e.message.lines.first&.chomp}")
        EXIT_CODES[:usage]
      end

      def description(job, pipeline)
        rows = [["input", input(pipeline)], ["steps", steps(pipeline)]]
        rows << ["output", pipeline.sink ? sink(pipeline.sink) : "stdout (JSON Lines)"]
        rows << ["rejects", sink(pipeline.rejects)] if pipeline.rejects
        rows << ["failures", sink(pipeline.failures)] if pipeline.failures
        rows << ["on_failure", policy(pipeline)]
        kind = job.is_a?(Transform) ? "transform" : "job"
        title = job.name ? "#{kind} #{job.name.inspect}" : kind
        ["#{@target}: #{title} OK", *rows.map { |label, text| "  #{label.ljust(10)} #{text}" }].join("\n")
      end

      def input(pipeline)
        name = pipeline.source ? pipeline.source.class.name : "stdin (JSON Lines)"
        pipeline.id_extractor ? "#{name} (id extractor)" : name
      end

      def steps(pipeline)
        return "none" if pipeline.steps.empty?

        pipeline.steps.map { |step| step.reason ? "#{step.name} #{step.reason.inspect}" : step.name }.join(", ")
      end

      def sink(adapter)
        adapter.batch ? "#{adapter.sink.class.name}, batch #{adapter.batch}" : adapter.sink.class.name
      end

      def policy(pipeline)
        return pipeline.on_failure.to_s unless pipeline.max_failures

        "#{pipeline.on_failure}, max_failures #{pipeline.max_failures}"
      end

    end
  end
end
