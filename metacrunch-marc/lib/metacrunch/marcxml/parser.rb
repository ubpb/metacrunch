# frozen_string_literal: true

require "ox"

module Metacrunch
  module Marcxml
    # The Ox SAX handler behind Marcxml.each: builds a Record per <record>
    # element and passes it to the block. Elements are matched by their
    # local name, so prefixes do not matter; other elements are ignored, and
    # inside a value their text too. Text is kept exactly (skip: :skip_none);
    # text and CDATA events are appended. Internal.
    class Parser < Ox::Sax

      OPTIONS = {skip: :skip_none, convert_special: true, smart: false}.freeze

      # Parses input (an object with readpartial or read) and passes each
      # Record to block. normalize: nil or :nfc.
      def self.run(input, normalize:, &block)
        parser = new(normalize, block)
        Ox.sax_parse(parser, input, **OPTIONS)
        parser.finish
      end

      def initialize(normalize, block)
        super()
        @normalize = normalize
        @block = block
        @names = {}
        @record = nil
        @field = nil
        @text = nil
        @kind = nil
        @skip = 0
        @target = nil
        @tag = nil
        @code = nil
      end

      def start_element(name)
        @target = nil
        return @skip += 1 if @text

        case local(name)
        when :record then start_record
        when :datafield then start_data_field if @record
        when :leader, :controlfield then start_value(local(name)) if @record
        when :subfield then start_value(:subfield) if @field
        end
      end

      def attr(name, value)
        case @target
        when :record then @record.type = utf8(value) if name == :type
        when :datafield then data_field_attr(name, value)
        when :controlfield then @tag = utf8(value) if name == :tag
        when :subfield then @code = utf8(value) if name == :code
        end
      end

      def text(value)
        @text << utf8(value) if @text && @skip.zero?
      end

      alias cdata text

      def end_element(name)
        @target = nil
        if @text
          return @skip -= 1 if @skip.positive?

          return finish_value
        end

        case local(name)
        when :datafield then finish_data_field if @field
        when :record then finish_record if @record
        end
      end

      # Ox reports here what is not well-formed.
      def error(message, line, column)
        raise ParseError.new(message, line:, column:)
      end

      # Raises if the input ended inside a record.
      def finish
        raise ParseError, "the input ended inside a record" if @record
      end

      private

      def local(name)
        @names[name] ||= begin
          text = name.name
          index = text.index(":")
          index ? text[(index + 1)..].to_sym : name
        end
      end

      def start_record
        @record = Record.new
        @field = nil
        @target = :record
      end

      def start_data_field
        @field = DataField.new("")
        @target = :datafield
      end

      def data_field_attr(name, value)
        case name
        when :tag then @field.tag = utf8(value)
        when :ind1 then @field.ind1 = indicator(value)
        when :ind2 then @field.ind2 = indicator(value)
        end
      end

      def start_value(kind)
        @kind = kind
        @text = String.new(encoding: Encoding::UTF_8)
        @tag = ""
        @code = ""
        @target = kind
      end

      def finish_value
        value = checked(@text)
        case @kind
        when :leader then @record.leader = value
        when :controlfield then @record.fields << ControlField.new(@tag, value)
        else @field.subfields << Subfield.new(@code, value)
        end
        @text = nil
        @kind = nil
      end

      def finish_data_field
        @record.fields << @field
        @field = nil
      end

      def finish_record
        record = @record
        @record = nil
        @field = nil
        @block.call(record)
      end

      # An empty indicator attribute is blank.
      def indicator(value) = value.empty? ? DataField::BLANK : utf8(value)

      # Ox returns binary strings for input without an XML declaration.
      def utf8(value) = value.force_encoding(Encoding::UTF_8)

      def checked(value)
        raise ParseError, "#{value_name}: invalid UTF-8" unless value.valid_encoding?
        return value if @normalize.nil? || value.ascii_only?

        value.unicode_normalize(:nfc)
      end

      def value_name
        case @kind
        when :leader then "leader"
        when :controlfield then "field #{@tag}"
        else "field #{@field.tag} $#{@code}"
        end
      end

    end
  end
end
