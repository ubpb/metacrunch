# frozen_string_literal: true

module Metacrunch
  module Marc
    module Xml
      # Writes a Record as MARCXML (Record#to_xml): one element per line,
      # indented by two spaces per level. indent goes before every element,
      # never into a value. Internal.
      module Serializer

        # Characters XML 1.0 cannot represent, also not as references: control
        # characters but tab and line breaks, and two noncharacters.
        CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F]/
        NONCHARACTERS = ["\uFFFE", "\uFFFF"].freeze

        TEXT = {"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\r" => "&#13;"}.freeze
        TEXT_SPECIAL = /[&<>\r]/
        ATTRIBUTE = TEXT.merge("\"" => "&quot;", "\t" => "&#9;", "\n" => "&#10;").freeze
        ATTRIBUTE_SPECIAL = /[&<>"\r\t\n]/

        module_function

        def record(record, namespace:, indent: "")
          xml = "#{indent}<record"
          xml << " xmlns=\"#{NAMESPACE}\"" if namespace
          xml << " type=\"#{attribute(record.type) { "type" }}\"" if record.type
          xml << ">\n"
          xml << "#{indent}  <leader>#{text(record.leader) { "leader" }}</leader>\n" if record.leader
          record.fields.each { field(xml, it, indent) }
          xml << "#{indent}</record>\n"
        end

        def field(xml, field, indent)
          return data_field(xml, field, indent) if field.is_a?(DataField)

          tag = attribute(field.tag) { location(field.tag) }
          xml << "#{indent}  <controlfield tag=\"#{tag}\">#{text(field.value) { location(field.tag) }}</controlfield>\n"
        end

        def data_field(xml, field, indent)
          tag = attribute(field.tag) { location(field.tag) }
          ind1 = attribute(field.ind1) { location(field.tag) }
          ind2 = attribute(field.ind2) { location(field.tag) }
          xml << "#{indent}  <datafield tag=\"#{tag}\" ind1=\"#{ind1}\" ind2=\"#{ind2}\">\n"
          field.subfields.each do |subfield|
            code = attribute(subfield.code) { location(field.tag, subfield.code) }
            value = text(subfield.value) { location(field.tag, subfield.code) }
            xml << "#{indent}    <subfield code=\"#{code}\">#{value}</subfield>\n"
          end
          xml << "#{indent}  </datafield>\n"
        end

        # The block gives the location for an error message; it runs only on
        # errors.
        def text(value, &) = escape(value, TEXT_SPECIAL, TEXT, &)

        def attribute(value, &) = escape(value, ATTRIBUTE_SPECIAL, ATTRIBUTE, &)

        # nil is written as "". Strings in other encodings are transcoded.
        # Raises SerializeError for invalid UTF-8 and for characters XML 1.0
        # cannot represent.
        def escape(value, pattern, table)
          string = value.to_s
          string = utf8(string) unless string.encoding == Encoding::UTF_8
          raise SerializeError, "#{yield}: invalid UTF-8 #{string.inspect}" unless string.valid_encoding?

          forbidden = unrepresentable(string)
          raise SerializeError, "#{yield}: #{forbidden.inspect} cannot be represented in XML 1.0" if forbidden

          string.match?(pattern) ? string.gsub(pattern, table) : string
        end

        # Binary strings are taken as UTF-8; strings in other encodings are
        # transcoded, or taken as UTF-8 if they cannot be.
        def utf8(string)
          return string.dup.force_encoding(Encoding::UTF_8) if string.encoding == Encoding::BINARY

          string.encode(Encoding::UTF_8)
        rescue EncodingError
          string.dup.force_encoding(Encoding::UTF_8)
        end

        # "field 245 $a", with invalid bytes shown as escapes.
        def location(tag, code = nil)
          where = "field #{readable(tag)}"
          code ? "#{where} $#{readable(code)}" : where
        end

        def readable(value)
          string = value.to_s.dup.force_encoding(Encoding::UTF_8)
          string.scrub { |bytes| bytes.unpack("C*").map { format("\\x%02X", it) }.join }
        end

        # The first character of string that XML 1.0 cannot represent, or nil.
        # Checks ASCII and non-ASCII apart; one regex with both is much slower.
        def unrepresentable(string)
          return string[CONTROL] if string.match?(CONTROL)
          return if string.ascii_only?

          NONCHARACTERS.find { string.include?(it) }
        end

      end
    end
  end
end
