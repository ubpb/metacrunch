# frozen_string_literal: true

module Metacrunch
  module Marc

    # Base class of the errors of this library.
    class Error < StandardError; end

    # Input that is not well-formed MARCXML. line and column are positions
    # in the input as Ox reports them, or nil.
    class ParseError < Error

      attr_reader :line, :column

      def initialize(message, line: nil, column: nil)
        @line = line
        @column = column
        super(line ? "#{message} (line #{line}, column #{column})" : message)
      end

    end

    # A record that cannot be written as MARCXML.
    class SerializeError < Error; end

  end
end
