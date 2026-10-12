# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A subfield of a data field: a code and a value, both Strings.
    class Subfield

      attr_accessor :code, :value

      def initialize(code, value)
        @code = code
        @value = value
      end

      def ==(other)
        other.instance_of?(Subfield) && other.code == code && other.value == value
      end

      alias eql? ==

      def hash = [Subfield, code, value].hash

      # MARC-in-JSON: {"a" => "Title"}.
      def to_h = {code => value}

      # "$aTitle", as in the mnemonic form of MarcEdit.
      def to_s = "$#{code}#{value}"

      alias inspect to_s

      private

      # dup and clone copy the strings, so a copy can be changed in place.
      def initialize_copy(source)
        super
        @code = source.code&.dup
        @value = source.value&.dup
      end

    end
  end
end
