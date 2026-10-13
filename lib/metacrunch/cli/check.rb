# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch check: loads the job, binds its parameters and builds the
    # pipeline. Opens nothing, reads no record, runs no hook. Parameter
    # values are not printed; they may contain secrets.
    class CheckCommand < JobCommand

      NAME = "check"
      SUMMARY = "Validate a job without running it"
      USAGE = "check [OPTIONS] NAME|FILE [JOB_PARAMS...] [ARGS...]"

      private

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
        rows << ["errors", sink(pipeline.errors)] if pipeline.errors
        rows << ["on_error", policy(pipeline)]
        title = job.name ? "job #{job.name.inspect}" : "job"
        ["#{@target}: #{title} OK", *rows.map { |label, text| "  #{label.ljust(9)} #{text}" }].join("\n")
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
        return pipeline.on_error.to_s unless pipeline.max_errors

        "#{pipeline.on_error}, max_errors #{pipeline.max_errors}"
      end

    end
  end
end
