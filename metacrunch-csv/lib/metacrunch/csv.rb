# frozen_string_literal: true

require "csv"
require "stringio"
require "metacrunch"
require_relative "csv/version"
require_relative "csv/errors"
require_relative "csv/columns"
require_relative "csv/lines"
require_relative "csv/reader"
require_relative "csv/writer"

module Metacrunch
  # CSV for metacrunch: a source (Reader) and a sink (Writer) on Ruby's csv.
  # Records are Hashes with String keys (or Arrays); values stay Strings.
  module Csv

    # The byte order marks the reader removes and the writer can write.
    BOMS = {
      Encoding::UTF_8 => "\xEF\xBB\xBF".b,
      Encoding::UTF_16LE => "\xFF\xFE".b,
      Encoding::UTF_16BE => "\xFE\xFF".b
    }.freeze

    class << self

      # The Encoding named encoding; raises ArgumentError unless col_sep and
      # quote_char are usable with it.
      def encoding(col_sep, quote_char, encoding)
        found = find(encoding)
        unless col_sep.is_a?(String) && !col_sep.empty?
          raise ArgumentError, "col_sep must be a non-empty String, got #{col_sep.inspect}"
        end
        unless quote_char.is_a?(String) && quote_char.length == 1 && quote_char != col_sep
          raise ArgumentError, "quote_char must be one character other than col_sep, got #{quote_char.inspect}"
        end

        [col_sep, quote_char].each { encodable(it, found) }
        found
      end

      # True for UTF-8 and the single-byte encodings (ISO-8859-1,
      # Windows-1252, ...): no byte of a character there looks like ASCII,
      # so Ruby's csv can parse the bytes.
      def bytewise?(encoding)
        return true if encoding == Encoding::UTF_8

        encoding.ascii_compatible? && (0x80..0xFF).all? { [it].pack("C").force_encoding(encoding).valid_encoding? }
      end

      private

      def find(name)
        encoding = begin
          Encoding.find(name)
        rescue ArgumentError, TypeError
          raise ArgumentError, "encoding must be the name of an encoding, got #{name.inspect}"
        end
        return encoding unless encoding.dummy?

        raise ArgumentError, "encoding #{encoding} has no byte order; use UTF-16LE, UTF-16BE or another encoding"
      end

      def encodable(text, encoding)
        text.encode(encoding)
      rescue EncodingError
        raise ArgumentError, "#{text.inspect} cannot be written in #{encoding}"
      end

    end

  end
end
