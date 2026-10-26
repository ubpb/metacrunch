# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The XML of cells, by the Ruby type of their values. Internal.
    module Cells

      # Excel keeps 15 significant digits; it would change longer Integers.
      MAX_DIGITS = 15
      MAX_TEXT = 32_767
      # Characters XML 1.0 does not allow (tab, LF and CR are allowed).
      INVALID_XML = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/
      # The "_" of text Excel would read as a character code (_x0041_ for
      # "A"), also in a chain (_x0041_x0042_).
      CHARACTER_CODE = /_(?=x\h{4}_)/
      ESCAPES = {"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;"}.freeze

      # A value or row that cannot be written; index: the column's index, or
      # nil for the whole row. Writer adds the record's position.
      class Unwritable < StandardError

        attr_reader :index

        def initialize(message, index: nil)
          @index = index
          super(message)
        end

      end

      module_function

      # The letters of the column at index (0-based): A, ..., Z, AA, ...
      def column(index)
        name = +""
        number = index + 1
        while number.positive?
          number, rest = (number - 1).divmod(26)
          name.prepend((65 + rest).chr)
        end
        name
      end

      # The XML of a cell at ref, or nil for nil. style: the index of a cell
      # format (1 is bold) or nil.
      def cell(value, ref, style = nil)
        case value
        when nil then nil
        when String then text(value, ref, style)
        when true, false then %(<c r="#{ref}"#{style_attribute(style)} t="b"><v>#{value ? 1 : 0}</v></c>)
        when Integer then number(integer(value), ref, style)
        when Float then number(float(value), ref, style)
        else
          # A BigDecimal, as from a database's NUMERIC column.
          return number(big_decimal(value), ref, style) if defined?(::BigDecimal) && value.is_a?(::BigDecimal)

          raise Unwritable, "is #{Columns.described(value)}; turn it into a String or a number in a step"
        end
      end

      def text(value, ref, style)
        %(<c r="#{ref}"#{style_attribute(style)} t="inlineStr"><is>#{text_element(value)}</is></c>)
      end

      def text_element(value)
        text = utf8(value)
        raise Unwritable, "has more than #{MAX_TEXT} characters" if text.length > MAX_TEXT
        raise Unwritable, "has a character that XML does not allow" if text.match?(INVALID_XML)

        preserve = text.match?(/\A\s|\s\z/) ? ' xml:space="preserve"' : ""
        # XML would read "\r\n" and "\r" as "\n"; Excel writes a carriage
        # return as a character code.
        "<t#{preserve}>#{escape(text.gsub(CHARACTER_CODE, "_x005F_").gsub("\r", "_x000D_"))}</t>"
      end

      def utf8(value)
        raise Unwritable, "is not valid #{value.encoding}" unless value.valid_encoding?
        return value if value.encoding == Encoding::UTF_8

        value.encode(Encoding::UTF_8)
      rescue EncodingError
        raise Unwritable, "has no UTF-8 form (it is #{value.encoding})"
      end

      def escape(text) = text.gsub(/[&<>"]/, ESCAPES)

      def integer(value)
        return value.to_s if value.abs < 10**MAX_DIGITS

        raise Unwritable, "has more than #{MAX_DIGITS} digits, which Excel cannot keep; turn it into a String in a step"
      end

      def float(value)
        return value.to_s if value.finite?

        raise Unwritable, "is #{value}, which Excel cannot store"
      end

      def big_decimal(value)
        raise Unwritable, "is #{value}, which Excel cannot store" unless value.finite?
        return value.to_s("F") if value.n_significant_digits <= MAX_DIGITS

        raise Unwritable, "has more than #{MAX_DIGITS} significant digits, which Excel cannot keep; turn it into a " \
                          "String in a step"
      end

      def number(text, ref, style) = %(<c r="#{ref}"#{style_attribute(style)}><v>#{text}</v></c>)

      def style_attribute(style) = style ? %( s="#{style}") : ""

    end
  end
end
