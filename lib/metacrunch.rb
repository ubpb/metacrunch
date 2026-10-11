# frozen_string_literal: true

require "logger"

require_relative "metacrunch/version"
require_relative "metacrunch/errors"
require_relative "metacrunch/invalid_record"
require_relative "metacrunch/record_logger"
require_relative "metacrunch/context"
require_relative "metacrunch/stats"
require_relative "metacrunch/stats_collector"
require_relative "metacrunch/result"
require_relative "metacrunch/live_stats"
require_relative "metacrunch/callable"
require_relative "metacrunch/step"
require_relative "metacrunch/sink_adapter"
require_relative "metacrunch/components"
require_relative "metacrunch/sink_outlet"
require_relative "metacrunch/processor"
require_relative "metacrunch/params"
require_relative "metacrunch/credentials"
require_relative "metacrunch/credentials/key"
require_relative "metacrunch/credentials/box"
require_relative "metacrunch/credentials/location"
require_relative "metacrunch/pipeline"
require_relative "metacrunch/builder"
require_relative "metacrunch/executor"
require_relative "metacrunch/executor/inline"
require_relative "metacrunch/executor/fork"
require_relative "metacrunch/executor/fork/frame"
require_relative "metacrunch/executor/fork/dump"
require_relative "metacrunch/executor/fork/worker"
require_relative "metacrunch/executor/fork/run"
require_relative "metacrunch/engine"
require_relative "metacrunch/job"
require_relative "metacrunch/loader"
require_relative "metacrunch/json_lines"

module Metacrunch

  LOG_FORMATTER = proc do |severity, time, _progname, message|
    "#{time.strftime("%H:%M:%S")} #{severity.ljust(5)} #{message}\n"
  end

  class << self

    attr_writer :logger

    # The default logger writes to stderr. Stdout is reserved for data.
    def logger
      @logger ||= build_logger($stderr)
    end

    def build_logger(io)
      Logger.new(io, level: Logger::INFO, formatter: LOG_FORMATTER)
    end

    # Defines a job. Inside a job file loaded with load_job, the job is
    # also registered with the loader.
    def job(name = nil, &)
      Job.new(name, &).tap { |job| Loader.register(job) }
    end

    def load_job(path, name: nil)
      Loader.load(path, name:)
    end

  end

end
