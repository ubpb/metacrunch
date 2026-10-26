# frozen_string_literal: true

require "ox"

module Metacrunch
  module Marc
    module Xml
      # The Ox SAX handler behind Xml.each: builds a Record per <record>
      # element and passes it to the block. Elements are matched by their
      # local name, so prefixes do not matter; other elements are ignored, and
      # inside a value their text too. Text is kept exactly (skip: :skip_none);
      # text and CDATA events are appended. Internal.
      class Parser < Ox::Sax

        OPTIONS = {skip: :skip_none, convert_special: true, smart: false}.freeze

        # Parses input (a StringSource, or an object with readpartial or read)
        # and passes each Record to block. normalize: nil or :nfc.
        def self.run(input, normalize:, &block)
          source = UntilNul.new(input)
          parser = new(normalize, block)
          parse(parser, source)
          raise ParseError, "a NUL byte at offset #{source.nul}, which XML does not allow" if source.nul

          parser.finish
        rescue EncodingError => e
          # Ox makes Symbols of names; invalid bytes in a name raise here.
          # Errors of the block are passed on as they are.
          raise if parser.nil? || parser.in_block?

          raise ParseError, "invalid UTF-8 in markup (#{e.message})"
        end

        # Runs Ox. What Ox reports once the input ends at a NUL byte, such as
        # an element not closed, gives way to the NUL; errors of the block
        # are passed on as they are.
        def self.parse(parser, source)
          Ox.sax_parse(parser, source, **OPTIONS)
        rescue ParseError
          raise if parser.in_block? || source.nul.nil?
        end
        private_class_method :parse

        def initialize(normalize, block)
          super()
          @normalize = normalize
          @block = block
          @names = {}
          # The fields of the record being read; nil outside a record.
          @fields = nil
          @leader = nil
          @type = nil
          # The subfields of the data field being read; nil outside one.
          @subfields = nil
          @field_tag = nil
          @ind1 = nil
          @ind2 = nil
          @text = nil
          @kind = nil
          @skip = 0
          @target = nil
          @tag = nil
          @code = nil
          @in_block = false
        end

        def start_element(name)
          @target = nil
          return @skip += 1 if @text

          case local(name)
          when :record then start_record
          when :datafield then start_data_field if @fields
          when :leader, :controlfield then start_value(local(name)) if @fields
          when :subfield then start_value(:subfield) if @subfields
          end
        end

        def attr(name, value)
          case @target
          when :record then @type = attribute(name, value) if name == :type
          when :datafield then data_field_attr(name, value)
          when :controlfield then @tag = attribute(name, value) if name == :tag
          when :subfield then @code = attribute(name, value) if name == :code
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
          when :datafield then finish_data_field if @subfields
          when :record then finish_record if @fields
          end
        end

        # Ox reports here what is not well-formed.
        def error(message, line, column)
          raise ParseError.new(message, line:, column:)
        end

        # Raises if the input ended inside a record.
        def finish
          raise ParseError, "the input ended inside a record" if @fields
        end

        # True while the block runs, so its errors are not taken for errors of
        # the input.
        def in_block? = @in_block

        private

        def local(name)
          @names[name] ||= begin
            text = name.name
            index = text.index(":")
            index ? text[(index + 1)..].to_sym : name
          end
        end

        def start_record
          @fields = []
          @leader = nil
          @type = nil
          @subfields = nil
          @target = :record
        end

        def start_data_field
          @subfields = []
          @field_tag = ""
          @ind1 = DataField::BLANK
          @ind2 = DataField::BLANK
          @target = :datafield
        end

        def data_field_attr(name, value)
          case name
          when :tag then @field_tag = attribute(name, value)
          when :ind1 then @ind1 = indicator(name, value)
          when :ind2 then @ind2 = indicator(name, value)
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
          when :leader then @leader = value
          when :controlfield then @fields << ControlField.new(@tag, value)
          else @subfields << Subfield.new(@code, value)
          end
          @text = nil
          @kind = nil
        end

        def finish_data_field
          @fields << DataField.new(@field_tag, @ind1, @ind2, @subfields)
          @subfields = nil
        end

        def finish_record
          record = Record.new(leader: @leader, type: @type, fields: @fields)
          @fields = nil
          @subfields = nil
          @in_block = true
          @block.call(record)
          @in_block = false
        end

        # An empty indicator attribute is blank.
        def indicator(name, value) = value.empty? ? DataField::BLANK : attribute(name, value)

        def attribute(name, value)
          value = utf8(value)
          raise ParseError, "invalid UTF-8 in attribute #{name}" unless value.valid_encoding?

          forbidden = Values.unrepresentable(value)
          raise ParseError, "attribute #{name}: #{forbidden.inspect} #{Values::UNREPRESENTABLE}" if forbidden

          value
        end

        # Ox returns binary strings for input without an XML declaration.
        def utf8(value) = value.force_encoding(Encoding::UTF_8)

        def checked(value) = Values.parsed(value, @normalize) { value_name }

        def value_name
          case @kind
          when :leader then "leader"
          when :controlfield then "field #{@tag}"
          else "field #{@field_tag} $#{@code}"
          end
        end

      end
    end
  end
end
