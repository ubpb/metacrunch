# frozen_string_literal: true

module Metacrunch
  # Logger for one record: prefixes every message with the record's id or
  # position, so log lines can be traced back to the input.
  class RecordLogger

    LEVELS = [:debug, :info, :warn, :error, :fatal].freeze

    def initialize(logger, label)
      @logger = logger
      @label = label
    end

    LEVELS.each do |level|
      define_method(level) do |message|
        @logger.public_send(level) { "[#{@label}] #{message}" }
      end
    end

  end
end
