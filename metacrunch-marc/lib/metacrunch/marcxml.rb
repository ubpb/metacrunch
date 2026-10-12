# frozen_string_literal: true

require "stringio"
require_relative "marcxml/version"
require_relative "marcxml/errors"
require_relative "marcxml/codes"
require_relative "marcxml/subfield"
require_relative "marcxml/control_field"
require_relative "marcxml/data_field"
require_relative "marcxml/filter"
require_relative "marcxml/record"
require_relative "marcxml/serializer"
require_relative "marcxml/string_source"
require_relative "marcxml/io_source"
require_relative "marcxml/parser"
require_relative "marcxml/splitter"

module Metacrunch
  # MARCXML for metacrunch: an ordered record model (Record, ControlField,
  # DataField, Subfield), a parser, a serializer, and a source (Reader) and
  # a sink (Writer). Only Reader and Writer depend on metacrunch.
  module Marcxml

    # The namespace of the MARC 21 XML schema.
    NAMESPACE = "http://www.loc.gov/MARC21/slim"

    # The values of normalize:.
    NORMALIZATIONS = [nil, :nfc].freeze

    class << self

      # The one record in xml, a String with one <record>, bare or in a
      # <collection>. Raises ParseError for none or more than one.
      def parse(xml, normalize: nil)
        raise ArgumentError, "xml must be a String, got #{xml.class}" unless xml.is_a?(String)

        records = each(xml, normalize:).to_a
        raise ParseError, "no record found" if records.empty?
        raise ParseError, "#{records.size} records found where one was expected (use Marcxml.each)" if records.size > 1

        records.first
      end

      # Yields every record of input: a String, or an object with
      # readpartial or read (a File, a Zlib::GzipReader, a pipe). Without a
      # block an Enumerator.
      def each(input, normalize: nil, &block)
        check_input(input)
        check_normalize(normalize)
        return enum_for(:each, input, normalize:) unless block

        Parser.run(source(input), normalize:, &block)
        nil
      end

      # Yields every record of input as a String from its start tag to its
      # end tag, without parsing it. Without a block an Enumerator.
      def each_xml(input, &block)
        check_input(input)
        return enum_for(:each_xml, input) unless block

        Splitter.new(input).each(&block)
        nil
      end

      # Raises ArgumentError unless normalize is nil or :nfc.
      def check_normalize(normalize)
        return if NORMALIZATIONS.include?(normalize)

        raise ArgumentError, "normalize must be nil or :nfc, got #{normalize.inspect}"
      end

      private

      # Ox is superlinear on a String and a StringIO; both reach it through
      # readpartial.
      def source(input)
        case input
        when String then StringSource.new(input)
        when StringIO then IoSource.new(input)
        else input
        end
      end

      def check_input(input)
        return if input.is_a?(String) || input.respond_to?(:readpartial) || input.respond_to?(:read)

        raise ArgumentError, "input must be a String or respond to #readpartial or #read, got #{input.class}"
      end

    end

  end
end

# The metacrunch components need the core above.
require_relative "marcxml/reader"
require_relative "marcxml/writer"
