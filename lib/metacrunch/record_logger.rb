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

    # Like Logger: a message or a block, which only runs if the level is
    # enabled. The predicates (debug?, info?, ...) are delegated.
    LEVELS.each do |level|
      define_method(level) do |message = nil, &block|
        @logger.public_send(level) { "[#{@label}] #{block && message.nil? ? block.call : message}" }
      end

      define_method(:"#{level}?") { @logger.public_send(:"#{level}?") }
    end

  end
end
