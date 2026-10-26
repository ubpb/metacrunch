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

      RECORD_END_BYTE = RECORD_TERMINATOR.ord
      private_constant :RECORD_END_BYTE

      class << self

        # The one record in string. Raises ParseError for none, more than one,
        # or bytes after it that are not a record.
        def parse(string, normalize: nil)
          raise ArgumentError, "string must be a String, got #{string.class}" unless string.is_a?(String)

          Marc.check_normalize(normalize)
          raws = each_raw(string).to_a
          raise ParseError, "no record found" if raws.empty?

          check_one(raws) if raws.size > 1

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
        # parsing it. Space, tab, line breaks and NUL between records and the
        # byte order marks of concatenated files are skipped; bytes at the
        # end without a terminator are yielded as they are and fail when
        # parsed. Without a block an Enumerator.
        def each_raw(input)
          Marc.check_input(input)
          return enum_for(:each_raw, input) unless block_given?

          Delimited.new(input, RECORD_TERMINATOR.b).each do |piece|
            start = start(piece)
            next if start.nil? || terminator_only?(piece, start)

            piece = piece.byteslice(start, piece.bytesize - start) if start.positive?
            yield piece.force_encoding(Encoding::UTF_8)
          end
          nil
        end

        private

        # Raises for more than one record, or for bytes after the record that
        # are not a record (they have no terminator).
        def check_one(raws)
          if raws.size == 2 && raws.last.getbyte(-1) != RECORD_END_BYTE
            raise ParseError, "bytes after the record that are not a record: #{raws.last.b.byteslice(0, 16).inspect}"
          end

          raise ParseError, "#{raws.size} records found where one was expected (use Marc::Iso2709.each)"
        end

        # A record terminator alone is no record and holds no data.
        def terminator_only?(piece, start) = start == piece.bytesize - 1 && piece.getbyte(start) == RECORD_END_BYTE

        # Where the record in piece starts: after space, tab, line breaks,
        # NUL and byte order marks (one starts each concatenated file); nil
        # if it has nothing else.
        def start(piece)
          start = piece.index(CONTENT)
          start = piece.index(CONTENT, start + BOM.bytesize) while start && piece.byteslice(start, BOM.bytesize) == BOM
          start
        end

      end

    end
  end
end
