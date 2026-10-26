# frozen_string_literal: true

module Metacrunch
  module Marc
    # The rule of every parser and serializer for the leader, tags,
    # indicators, codes and values: valid UTF-8, and no character that XML
    # 1.0 cannot represent (control characters but tab and line breaks, and
    # two noncharacters). So whatever one format reads, the others can
    # write, and the separators of ISO 2709 never reach a value. Internal.
    module Values

      # Characters XML 1.0 cannot represent, also not as references: control
      # characters but tab and line breaks, and two noncharacters.
      CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F]/
      NONCHARACTERS = ["\uFFFE", "\uFFFF"].freeze
      UNREPRESENTABLE = "cannot be represented in XML 1.0"

      module_function

      # The first character of string that XML 1.0 cannot represent, or nil.
      # Checks ASCII and non-ASCII apart; one regex with both is much slower.
      def unrepresentable(string)
        return string[CONTROL] if string.match?(CONTROL)
        return if string.ascii_only?

        NONCHARACTERS.find { string.include?(it) }
      end

      # What breaks the rule in string, a String in UTF-8, or nil.
      def problem(string)
        return "invalid UTF-8" unless string.valid_encoding?

        forbidden = unrepresentable(string)
        "#{forbidden.inspect} #{UNREPRESENTABLE}" if forbidden
      end

      # value as a parser keeps it: checked and, with normalize: :nfc, in NFC.
      # Strings in other encodings are taken as the serializers take them.
      # Raises ParseError "<place>: <problem>"; the block gives the place and
      # runs only on errors.
      def parsed(value, normalize)
        value = utf8(value) unless value.encoding == Encoding::UTF_8
        problem = problem(value)
        raise ParseError, "#{yield}: #{problem}" if problem
        return value if normalize.nil? || value.ascii_only?

        value.unicode_normalize(:nfc)
      end

      # value as a serializer writes it: a String in UTF-8 (nil is ""; other
      # objects give their to_s). Raises SerializeError "<place>: <problem>";
      # the block gives the place and runs only on errors.
      def serializable(value)
        string = value.to_s
        string = utf8(string) unless string.encoding == Encoding::UTF_8
        raise SerializeError, "#{yield}: invalid UTF-8 #{string.inspect}" unless string.valid_encoding?

        forbidden = unrepresentable(string)
        raise SerializeError, "#{yield}: #{forbidden.inspect} #{UNREPRESENTABLE}" if forbidden

        string
      end

      # Binary strings are taken as UTF-8; strings in other encodings are
      # transcoded, or taken as UTF-8 if they cannot be.
      def utf8(string)
        return string.dup.force_encoding(Encoding::UTF_8) if string.encoding == Encoding::BINARY

        string.encode(Encoding::UTF_8)
      rescue EncodingError
        string.dup.force_encoding(Encoding::UTF_8)
      end

      # "field 245 $a", with invalid bytes and control characters shown as
      # escapes.
      def location(tag, code = nil)
        where = "field #{readable(tag)}"
        code ? "#{where} $#{readable(code)}" : where
      end

      # value for a message: invalid bytes and control characters as \\x..
      # escapes, so no terminal escape sequence of the data reaches a log.
      def readable(value)
        string = value.to_s.dup.force_encoding(Encoding::UTF_8).scrub { escaped(it) }
        string.match?(CONTROL) ? string.gsub(CONTROL) { escaped(it) } : string
      end

      def escaped(bytes) = bytes.unpack("C*").map { format("\\x%02X", it) }.join

    end
  end
end
