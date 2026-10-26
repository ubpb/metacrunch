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
require_relative "marc/xml/io_source"
require_relative "marc/xml/parser"
require_relative "marc/xml/splitter"
require_relative "marc/iso2709"
require_relative "marc/iso2709/parser"

module Metacrunch
  # MARC for metacrunch: an ordered record model (Record, ControlField,
  # DataField, Subfield) with parsers and serializers for MARCXML (Xml),
  # ISO 2709 (Iso2709) and MARC-in-JSON (Json), and a source (Reader) and a
  # sink (Writer). Only Reader and Writer depend on metacrunch.
  module Marc

    # The values of normalize:.
    NORMALIZATIONS = [nil, :nfc].freeze

    class << self

      # Raises ArgumentError unless normalize is nil or :nfc.
      def check_normalize(normalize)
        return if NORMALIZATIONS.include?(normalize)

        raise ArgumentError, "normalize must be nil or :nfc, got #{normalize.inspect}"
      end

      # Raises ArgumentError unless input is a String or responds to
      # readpartial or read. Internal.
      def check_input(input)
        return if input.is_a?(String) || input.respond_to?(:readpartial) || input.respond_to?(:read)

        raise ArgumentError, "input must be a String or respond to #readpartial or #read, got #{input.class}"
      end

    end

  end
end

# The metacrunch components need the core above.
require_relative "marc/reader"
require_relative "marc/writer"
