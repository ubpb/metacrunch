# frozen_string_literal: true

require_relative "marc/version"
require_relative "marc/errors"
require_relative "marc/values"
require_relative "marc/codes"
require_relative "marc/tags"
require_relative "marc/subfield"
require_relative "marc/control_field"
require_relative "marc/data_field"
require_relative "marc/filter"
require_relative "marc/record"
require_relative "marc/delimited"
require_relative "marc/xml"
require_relative "marc/xml/serializer"
require_relative "marc/xml/string_source"
require_relative "marc/xml/until_nul"
require_relative "marc/xml/parser"
require_relative "marc/xml/splitter"
require_relative "marc/iso2709"
require_relative "marc/iso2709/parser"
require_relative "marc/iso2709/serializer"
require_relative "marc/json"
require_relative "marc/json/parser"
require_relative "marc/json/serializer"
require_relative "marc/formats"
require_relative "marc/lookahead"

module Metacrunch
  # MARC for metacrunch: an ordered record model (Record, ControlField,
  # DataField, Subfield) with parsers and serializers for MARCXML (Xml),
  # ISO 2709 (Iso2709) and MARC-in-JSON (Json), and a source (Reader) and a
  # sink (Writer). Only Reader and Writer depend on metacrunch.
  module Marc

    # The values of normalize:.
    NORMALIZATIONS = [nil, :nfc].freeze

    # Internal: a UTF-8 byte order mark, and the bytes that are not skipped
    # before a record (all but space, tab, line breaks and NUL), for the
    # format modules and detection.
    BOM = "\xEF\xBB\xBF".b
    CONTENT = /[^ \t\r\n\0]/n
    private_constant :BOM, :CONTENT

    class << self

      # The one record in string, in the format its first bytes show (see
      # Formats): MARCXML, ISO 2709 or MARC-in-JSON. Raises ParseError for
      # none, several or another format. It is the step that parses what the
      # Reader yields with parse: false.
      def parse(string, normalize: nil)
        raise ArgumentError, "string must be a String, got #{string.class}" unless string.is_a?(String)

        check_normalize(normalize)
        format, head = Formats.detect { string.byteslice(0, it) }
        raise ParseError, "no record found" if format == :none

        format = :iso2709 if format == :unknown && Formats.iso2709_record?(string)
        raise ParseError, Formats.unknown(head) if format == :unknown

        Formats.library(format).parse(string, normalize:)
      end

      # Yields every record of input (a String, or an object with
      # readpartial or read: a File, a Zlib::GzipReader, a pipe) in the
      # format its first bytes show (see Formats). Raises ParseError for
      # another format, and at the first record that cannot be read. Without
      # a block an Enumerator. Unlike the Reader it reads one document, takes
      # no paths and unpacks no gzip or tar.
      def each(input, normalize: nil, &block)
        check_input(input)
        check_normalize(normalize)
        return enum_for(:each, input, normalize:) unless block

        input = Lookahead.new(input) unless input.is_a?(String)
        format = stream_format(input)
        Formats.library(format).each(input, normalize:, &block) unless format == :none
        nil
      end

      # Raises ArgumentError unless normalize is nil or :nfc.
      def check_normalize(normalize)
        return if NORMALIZATIONS.include?(normalize)

        raise ArgumentError, "normalize must be nil or :nfc, got #{normalize.inspect}"
      end

      # Raises ArgumentError unless input is a String or responds to
      # readpartial or read. A Pathname has read, but gives the first bytes
      # on every call. Internal.
      def check_input(input)
        if input.is_a?(Pathname)
          raise ArgumentError, %(input is a Pathname; pass an open File instead: File.open(path, "rb"))
        end
        return if input.is_a?(String) || input.respond_to?(:readpartial) || input.respond_to?(:read)

        raise ArgumentError, "input must be a String or respond to #readpartial or #read, got #{input.class}"
      end

      private

      # The format of input (a String or a Lookahead) for each. Peeks from
      # one byte on, as the Reader does: a pipe that pauses after a short
      # first record must not hold it back.
      def stream_format(input)
        peek = input.is_a?(String) ? ->(length) { input.byteslice(0, length) } : input.method(:peek)
        format, = Formats.detect(1, &peek)
        case format
        when :array then raise ParseError, Formats::ARRAY
        # Detection may have looked at one byte only; the message shows more.
        when :unknown then raise ParseError, Formats.unknown(peek.call(Formats::WINDOW))
        else format
        end
      end

    end

  end
end

# The metacrunch components need the core above.
require_relative "marc/reader"
require_relative "marc/writer"
