# frozen_string_literal: true

module Metacrunch
  module Marc

    # Base class of the errors of this library.
    class Error < StandardError; end

    # Input that a parser cannot read as MARCXML, ISO 2709 or MARC-in-JSON,
    # or whose values break the rule of all formats (see Values). line and
    # column are positions in MARCXML as Ox reports them, else nil; the
    # messages of the other formats say where instead.
    class ParseError < Error

      attr_reader :line, :column

      def initialize(message, line: nil, column: nil)
        @line = line
        @column = column
        super(line ? "#{message} (line #{line}, column #{column})" : message)
      end

    end

    # A record that a serializer cannot write in its format.
    class SerializeError < Error; end

  end
end
