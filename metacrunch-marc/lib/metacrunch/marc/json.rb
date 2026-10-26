# frozen_string_literal: true

require "json"

module Metacrunch
  module Marc
    # MARC-in-JSON (https://github.com/marc4j/marc4j/wiki/MARC-in-JSON-Description):
    # Record#to_h as JSON, one record per line (JSON Lines). Read by
    # Json::Parser, written by Json::Serializer.
    module Json

      NEWLINE = "\n".b
      private_constant :NEWLINE

      class << self

        # The one record in string: one JSON object, also over several lines.
        # Raises ParseError for anything else.
        def parse(string, normalize: nil)
          raise ArgumentError, "string must be a String, got #{string.class}" unless string.is_a?(String)

          Marc.check_normalize(normalize)
          Parser.line(string, normalize:)
        end

        # Yields the record of every line of input: a String, or an object
        # with readpartial or read. Raises ParseError at the first line that
        # cannot be read. Without a block an Enumerator.
        def each(input, normalize: nil, &block)
          Marc.check_input(input)
          Marc.check_normalize(normalize)
          return enum_for(:each, input, normalize:) unless block

          each_raw(input) { |line| yield Parser.line(line, normalize:) }
        end

        # Yields every line of input that is not blank as a String in UTF-8
        # (possibly invalid), without its line break and without a byte
        # order mark at its start. Without a block an Enumerator.
        def each_raw(input)
          Marc.check_input(input)
          return enum_for(:each_raw, input) unless block_given?

          Delimited.new(input, NEWLINE).each do |piece|
            line = piece.chomp
            line.delete_prefix!(BOM)
            yield line.force_encoding(Encoding::UTF_8) unless line.strip.empty?
          end
          nil
        end

      end

    end
  end
end
