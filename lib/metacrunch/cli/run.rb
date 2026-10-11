# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch run: runs a job. A job without source reads JSON Lines from
    # stdin, a job without sink writes them to stdout.
    class RunCommand < JobCommand

      NAME = "run"
      SUMMARY = "Run a job"
      USAGE = "run [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]"

      private

      def execute_job(job, argv)
        pipeline = RunOptions.new.apply(build_pipeline(job, argv), stdin: @stdin, stdout: @stdout)
        report(Engine.new(pipeline).run)
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
