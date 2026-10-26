# frozen_string_literal: true

module Metacrunch
  module Marc
    # A control field (001-009 in MARC 21): a tag and a value. The tag is
    # fixed (see Record); the value can be changed.
    class ControlField

      attr_reader :tag
      attr_accessor :value

      def initialize(tag, value)
        @tag = Tags.fix(tag)
        @value = value
      end

      # value[index], e.g. field[35..37] for the language in 008; nil if
      # there is no value.
      def [](index) = value&.[](index)

      def ==(other)
        other.instance_of?(ControlField) && other.tag == tag && other.value == value
      end

      alias eql? ==

      def hash = [ControlField, tag, value].hash

      # MARC-in-JSON: {"001" => "123"}.
      def to_h = {tag => value}

      # "=001  123", as in the mnemonic form of MarcEdit.
      def to_s = "=#{tag}  #{value}"

      alias inspect to_s

      private

      def initialize_copy(source)
        super
        @value = source.value&.dup
      end

    end
  end
end
