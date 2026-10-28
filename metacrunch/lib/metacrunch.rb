# frozen_string_literal: true

require "logger"

require_relative "metacrunch/version"
require_relative "metacrunch/errors"
require_relative "metacrunch/invalid_record"
require_relative "metacrunch/flush"
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
require_relative "metacrunch/names"
require_relative "metacrunch/params"
require_relative "metacrunch/credentials"
require_relative "metacrunch/credentials/key"
require_relative "metacrunch/credentials/box"
require_relative "metacrunch/credentials/location"
require_relative "metacrunch/credentials/store"
require_relative "metacrunch/params_file"
require_relative "metacrunch/pipeline"
require_relative "metacrunch/recipe_params"
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
require_relative "metacrunch/transform"
require_relative "metacrunch/command"
require_relative "metacrunch/command_builder"
require_relative "metacrunch/command_scope"
require_relative "metacrunch/loader"
require_relative "metacrunch/use_context"
require_relative "metacrunch/project"
require_relative "metacrunch/files"
require_relative "metacrunch/input"
require_relative "metacrunch/output"
require_relative "metacrunch/json_lines"
require_relative "metacrunch/run_options"
require_relative "metacrunch/invoker"

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

    # Defines a job. Inside a file that Loader loads, the job is also
    # registered with the loader.
    def job(name = nil, desc: nil, &)
      Job.new(name, desc:, &).tap { |job| Loader.register(job) }
    end

    # Defines a transform. Like job, it is registered with the loader inside
    # a file that Loader loads.
    def transform(name = nil, desc: nil, &)
      Transform.new(name, desc:, &).tap { |transform| Loader.register(transform) }
    end

    # Defines a command. Like job, it is registered with the loader inside
    # a file that Loader loads.
    def command(name, desc: nil, &)
      Command.new(name, desc:, &).tap { |command| Loader.register(command) }
    end

    def load_job(path, name: nil)
      Loader.load(path, name:, kind: Job, hint: "select one with name:")
    end

    def load_transform(path, name: nil)
      Loader.load(path, name:, kind: Transform, hint: "select one with name:")
    end

    def load_command(path, name: nil)
      Loader.load(path, name:, kind: Command, hint: "select one with name:")
    end

    # Loads the job, transform and command files that match globs into the
    # project whose Metacrunchfile is being loaded (see Project#load_files).
    def load_files(*globs)
      project = Project.loading || raise(ProjectError, "load_files works only in a Metacrunchfile")
      project.load_files(globs)
    end

    # The project of the nearest Metacrunchfile at or above dir.
    def load_project(dir = Dir.pwd) = Project.load(dir)

  end

end
