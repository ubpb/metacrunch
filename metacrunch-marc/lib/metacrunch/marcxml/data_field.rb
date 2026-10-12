# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A data field: a tag, two indicators and an ordered Array of Subfields.
    # A blank indicator is " ". The tag is fixed (see Record); indicators and
    # subfields can be changed.
    class DataField

      BLANK = " "

      attr_reader :tag, :ind1, :ind2

      # subfields: Subfields or [code, value] pairs.
      def initialize(tag, ind1 = BLANK, ind2 = BLANK, subfields = [])
        @tag = Tags.fix(tag)
        self.ind1 = ind1
        self.ind2 = ind2
        @subfields = subfields.map { subfield(it) }
      end

      # nil becomes " ".
      def ind1=(value)
        @ind1 = value.nil? ? BLANK : value
      end

      # nil becomes " ".
      def ind2=(value)
        @ind2 = value.nil? ? BLANK : value
      end

      # Without codes the field's own Array (changes affect the field), with
      # codes a new Array of the subfields with these codes, in field order.
      # Codes are Strings, also in Arrays.
      def subfields(*codes)
        codes = Codes.check(codes)
        codes.empty? ? @subfields : @subfields.select { codes.include?(it.code) }
      end

      # The values of the subfields with these codes (all without codes), in
      # field order.
      def values(*codes) = subfields(*codes).map(&:value)

      # The first value of these codes (of any code without codes), or nil.
      def value(*codes)
        codes = Codes.check(codes)
        found = codes.empty? ? @subfields.first : @subfields.find { codes.include?(it.code) }
        found&.value
      end

      def [](code) = value(code)

      # The values of these codes joined, or nil if there is none.
      def join(*codes, separator: " ")
        found = values(*codes)
        found.empty? ? nil : found.join(separator)
      end

      # Appends a subfield. Returns self.
      def add(code, value)
        @subfields << Subfield.new(code, value)
        self
      end

      # Removes the subfields with these codes. Returns them. Without codes
      # it raises, so an empty list cannot clear a field by accident.
      def remove(*codes)
        codes = Codes.check(codes)
        raise ArgumentError, "remove needs codes; subfields.clear removes all subfields" if codes.empty?

        removed = []
        @subfields.reject! do |subfield|
          match = codes.include?(subfield.code)
          removed << subfield if match
          match
        end
        removed
      end

      def ==(other)
        other.instance_of?(DataField) && other.tag == tag && other.ind1 == ind1 && other.ind2 == ind2 &&
          other.subfields == subfields
      end

      alias eql? ==

      def hash = [DataField, tag, ind1, ind2, @subfields].hash

      # MARC-in-JSON: {"245" => {"ind1" => "1", "ind2" => "0", "subfields" => [{"a" => "Title"}]}}.
      def to_h
        {tag => {"ind1" => ind1, "ind2" => ind2, "subfields" => @subfields.map(&:to_h)}}
      end

      # "=245  10$aTitle", as in the mnemonic form of MarcEdit; a blank
      # indicator is "\".
      def to_s = "=#{tag}  #{mnemonic(ind1)}#{mnemonic(ind2)}#{@subfields.join}"

      alias inspect to_s

      private

      def initialize_copy(source)
        super
        @ind1 = source.ind1.dup
        @ind2 = source.ind2.dup
        @subfields = source.subfields.map(&:dup)
      end

      def subfield(value)
        return value if value.is_a?(Subfield)
        return Subfield.new(*value) if value.is_a?(Array) && value.size == 2

        raise ArgumentError, "a subfield must be a Subfield or a [code, value] pair, got #{value.inspect}"
      end

      def mnemonic(indicator) = indicator == BLANK ? "\\" : indicator

    end
  end
end
