# frozen_string_literal: true

require "logger"

require_relative "metacrunch/version"
require_relative "metacrunch/errors"
require_relative "metacrunch/record_logger"
require_relative "metacrunch/context"

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

  end

end
