# frozen_string_literal: true

module Metacrunch
  module Marc
    module Xml
      # Writes a Record as MARCXML (Record#to_xml): one element per line,
      # indented by two spaces per level. indent goes before every element,
      # never into a value. Internal.
      module Serializer

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

          tag = attribute(field.tag) { Values.location(field.tag) }
          value = text(field.value) { Values.location(field.tag) }
          xml << "#{indent}  <controlfield tag=\"#{tag}\">#{value}</controlfield>\n"
        end

        def data_field(xml, field, indent)
          tag = attribute(field.tag) { Values.location(field.tag) }
          ind1 = attribute(field.ind1) { Values.location(field.tag) }
          ind2 = attribute(field.ind2) { Values.location(field.tag) }
          xml << "#{indent}  <datafield tag=\"#{tag}\" ind1=\"#{ind1}\" ind2=\"#{ind2}\">\n"
          field.subfields.each do |subfield|
            code = attribute(subfield.code) { Values.location(field.tag, subfield.code) }
            value = text(subfield.value) { Values.location(field.tag, subfield.code) }
            xml << "#{indent}    <subfield code=\"#{code}\">#{value}</subfield>\n"
          end
          xml << "#{indent}  </datafield>\n"
        end

        # The block gives the location for an error message; it runs only on
        # errors.
        def text(value, &) = escape(value, TEXT_SPECIAL, TEXT, &)

        def attribute(value, &) = escape(value, ATTRIBUTE_SPECIAL, ATTRIBUTE, &)

        # nil is written as "". Strings in other encodings are transcoded.
        # Raises SerializeError for values that break the common rule (see
        # Values); the block gives the place.
        def escape(value, pattern, table, &)
          string = Values.serializable(value, &)
          string.match?(pattern) ? string.gsub(pattern, table) : string
        end

      end
    end
  end
end
