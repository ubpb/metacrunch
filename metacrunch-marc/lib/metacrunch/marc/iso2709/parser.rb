# frozen_string_literal: true

module Metacrunch
  module Marc
    module Iso2709
      # Builds a Record from one ISO 2709 record that ends with its record
      # terminator. The terminators decide, not the lengths: the directory
      # runs to the first field terminator, the data is split on field
      # terminators, and a field with a subfield delimiter is a data field.
      # Record length, base address and field lengths are not used; starts
      # must not decrease, so data in another order than the directory fails
      # instead of pairing tags with the wrong data. Internal.
      class Parser

        ENTRY_LENGTH = 12
        RECORD_END = RECORD_TERMINATOR.b
        FIELD_END = FIELD_TERMINATOR.b
        DELIMITER = SUBFIELD_DELIMITER.b
        DIGITS = "0-9"
        MARC8 = "leader/09 says MARC-8; convert the file to UTF-8 first, e.g. " \
                "yaz-marcdump -f MARC-8 -t UTF-8 -o marc -l 9=97 in.mrc > out.mrc"

        def self.parse(raw, normalize:) = new(raw, normalize).record

        def initialize(raw, normalize)
          @raw = raw.b
          @normalize = normalize
        end

        # Checks the data of all fields at once; only if that fails, field by
        # field, to name the place.
        def record
          raise ParseError, "the input ended inside a record" unless @raw.end_with?(RECORD_END)

          @leader = leader
          tags, data_start = directory
          data = @raw.byteslice(data_start, @raw.bytesize - data_start - 1)
          pieces = pieces(data, tags.size)
          clean = clean?(data)
          fields = Array.new(tags.size) { field(tags[it], pieces[it], clean) }
          locate(fields) unless clean
          Record.new(leader: @leader, fields:)
        end

        private

        def leader
          raise ParseError, "the record ends inside its leader of 24 bytes" if @raw.bytesize <= LEADER_LENGTH

          leader = @raw.byteslice(0, LEADER_LENGTH)
          unless leader.ascii_only?
            raise ParseError, "leader: an ISO 2709 leader has 24 ASCII characters, got #{leader.inspect}"
          end

          Values.parsed(leader.force_encoding(Encoding::UTF_8), nil) { "leader" }
        end

        # The tags of the directory and where the data starts.
        def directory
          directory_end = @raw.index(FIELD_END, LEADER_LENGTH)
          raise ParseError, "the directory has no end (no field terminator)" unless directory_end

          length = directory_end - LEADER_LENGTH
          unless (length % ENTRY_LENGTH).zero?
            raise ParseError, "the directory has #{length} bytes, not a multiple of #{ENTRY_LENGTH}"
          end

          directory = @raw.byteslice(LEADER_LENGTH, length)
          clean = directory.ascii_only? && !directory.match?(Values::CONTROL)
          previous = 0
          tags = Array.new(length / ENTRY_LENGTH) do |index|
            tag = directory.byteslice(index * ENTRY_LENGTH, 3)
            check_tag(tag, index + 1) unless clean
            tag.force_encoding(Encoding::UTF_8)
            previous = start(directory.byteslice((index * ENTRY_LENGTH) + 7, 5), previous, index + 1, tag)
            tag
          end
          [tags, directory_end + 1]
        end

        def check_tag(tag, number)
          unless tag.ascii_only?
            raise ParseError, "directory entry #{number}: the tag #{tag.inspect} is not 3 ASCII characters"
          end

          problem = Values.problem(tag.dup.force_encoding(Encoding::UTF_8))
          raise ParseError, "directory entry #{number}: the tag #{problem}" if problem
        end

        # The start of a directory entry as a number.
        def start(text, previous, number, tag)
          unless text.count(DIGITS) == 5
            raise ParseError, "directory entry #{number} (#{tag}): the start #{text.inspect} is not 5 digits"
          end

          start = text.to_i
          if start < previous
            raise ParseError, "directory entry #{number} (#{tag}): the start #{start} is less than the start " \
                              "before it (#{previous})"
          end

          start
        end

        # The fields of data; a last field terminator may be missing.
        def pieces(data, count)
          pieces = data.split(FIELD_END, -1)
          pieces.pop if data.end_with?(FIELD_END)
          return pieces if pieces.size == count

          raise ParseError, "the directory has #{count} entries, the data #{pieces.size} fields"
        end

        # Whether all fields keep to the common rule (the separators aside).
        def clean?(data)
          text = data.dup.force_encoding(Encoding::UTF_8)
          text.valid_encoding? && !text.match?(FORBIDDEN) &&
            (text.ascii_only? || Values::NONCHARACTERS.none? { text.include?(it) })
        end

        def field(tag, piece, clean)
          delimiter = piece.index(DELIMITER)
          return ControlField.new(tag, value(piece.force_encoding(Encoding::UTF_8), clean)) unless delimiter

          indicators = piece.byteslice(0, delimiter).force_encoding(Encoding::UTF_8)
          unless indicators.length == 2
            raise ParseError,
                  "field #{Values.readable(tag)}: ISO 2709 indicators are 2 characters, got #{indicators.inspect}"
          end

          parts = piece.byteslice(delimiter + 1, piece.bytesize - delimiter - 1).split(DELIMITER, -1)
          subfields = parts.map do |part|
            raise ParseError, "field #{Values.readable(tag)}: a subfield without a code" if part.empty?

            part.force_encoding(Encoding::UTF_8)
            Subfield.new(part[0], value(part[1..], clean))
          end
          DataField.new(tag, indicators[0], indicators[1], subfields)
        end

        # A value, in NFC with normalize: :nfc. Values of a record that is
        # not clean are left as they are; locate raises for it.
        def value(text, clean)
          return text unless clean && @normalize && !text.ascii_only?

          text.unicode_normalize(:nfc)
        end

        # Raises for the first indicators, code or value that breaks the
        # common rule.
        def locate(fields)
          fields.each do |field|
            next check(field.value) { Values.location(field.tag) } if field.is_a?(ControlField)

            check(field.ind1 + field.ind2) { "#{Values.location(field.tag)} indicators" }
            field.subfields.each do |subfield|
              check(subfield.code) { Values.location(field.tag, subfield.code) }
              check(subfield.value) { Values.location(field.tag, subfield.code) }
            end
          end
        end

        def check(text)
          problem = Values.problem(text)
          return unless problem

          problem = "#{problem}; #{MARC8}" if @leader[9] == " " && marc8?(problem, text)
          raise ParseError, "#{yield}: #{problem}"
        end

        # Signs of MARC-8: bytes that are not UTF-8 (its diacritics), or the
        # escape that switches to another script (Cyrillic, Greek, Hebrew,
        # Arabic, CJK).
        def marc8?(problem, text) = problem == "invalid UTF-8" || text.include?("\e")

      end
    end
  end
end
