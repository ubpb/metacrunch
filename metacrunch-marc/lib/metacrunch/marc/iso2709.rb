# frozen_string_literal: true

module Metacrunch
  module Marc
    # ISO 2709 ("binary MARC", .mrc) in UTF-8: records framed by the record
    # terminator and read by a parser that trusts the terminators, not the
    # lengths (Iso2709::Parser); written by Record#to_iso2709
    # (Iso2709::Serializer).
    module Iso2709

      RECORD_TERMINATOR = "\x1D"
      FIELD_TERMINATOR = "\x1E"
      SUBFIELD_DELIMITER = "\x1F"

      # Internal: the length of a leader, and the characters the common rule
      # forbids in data that holds field terminators and subfield delimiters.
      LEADER_LENGTH = 24
      FORBIDDEN = /[\x00-\x08\x0B\x0C\x0E-\x1D]/

      BOM = "\xEF\xBB\xBF".b
      # Bytes that are not skipped between records: all but space, tab, line
      # breaks and NUL.
      CONTENT = /[^ \t\r\n\0]/n
      private_constant :BOM, :CONTENT

      class << self

        # The one record in string. Raises ParseError for none or more than
        # one.
        def parse(string, normalize: nil)
          raise ArgumentError, "string must be a String, got #{string.class}" unless string.is_a?(String)

          Marc.check_normalize(normalize)
          raws = each_raw(string).to_a
          raise ParseError, "no record found" if raws.empty?
          if raws.size > 1
            raise ParseError, "#{raws.size} records found where one was expected (use Marc::Iso2709.each)"
          end

          Parser.parse(raws.first, normalize:)
        end

        # Yields every record of input: a String, or an object with
        # readpartial or read. Raises ParseError at the first record that
        # cannot be read. Without a block an Enumerator.
        def each(input, normalize: nil, &block)
          Marc.check_input(input)
          Marc.check_normalize(normalize)
          return enum_for(:each, input, normalize:) unless block

          each_raw(input) { |raw| yield Parser.parse(raw, normalize:) }
        end

        # Yields every record of input as a String in UTF-8 (possibly
        # invalid) up to and including its record terminator, without
        # parsing it. Space, tab, line breaks and NUL between records and a
        # byte order mark at the start are skipped; bytes at the end without
        # a terminator are yielded as they are and fail when parsed. Without
        # a block an Enumerator.
        def each_raw(input)
          Marc.check_input(input)
          return enum_for(:each_raw, input) unless block_given?

          first = true
          Delimited.new(input, RECORD_TERMINATOR.b).each do |piece|
            piece = piece.delete_prefix(BOM) if first
            first = false
            start = piece.index(CONTENT)
            next unless start

            piece = piece.byteslice(start, piece.bytesize - start) if start.positive?
            yield piece.force_encoding(Encoding::UTF_8)
          end
          nil
        end

      end

    end
  end
end
