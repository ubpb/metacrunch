# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Writes a Record as MARCXML (Record#to_xml): one element per line,
    # indented by two spaces per level. Internal.
    module Serializer

      # Characters XML 1.0 cannot represent, also not as references.
      FORBIDDEN = /[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]/

      TEXT = {"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\r" => "&#13;"}.freeze
      ATTRIBUTE = TEXT.merge("\"" => "&quot;", "\t" => "&#9;", "\n" => "&#10;").freeze

      module_function

      def record(record, namespace:)
        xml = +"<record"
        xml << " xmlns=\"#{NAMESPACE}\"" if namespace
        xml << " type=\"#{attribute(record.type, "type")}\"" if record.type
        xml << ">\n"
        xml << "  <leader>#{text(record.leader, "leader")}</leader>\n" if record.leader
        record.fields.each { field(xml, it) }
        xml << "</record>\n"
      end

      def field(xml, field)
        where = "field #{field.tag}"
        tag = attribute(field.tag, where)
        if field.is_a?(ControlField)
          xml << "  <controlfield tag=\"#{tag}\">#{text(field.value, where)}</controlfield>\n"
        else
          data_field(xml, field, tag, where)
        end
      end

      def data_field(xml, field, tag, where)
        xml << "  <datafield tag=\"#{tag}\" ind1=\"#{attribute(field.ind1, where)}\" " \
               "ind2=\"#{attribute(field.ind2, where)}\">\n"
        field.subfields.each do |subfield|
          at = "#{where} $#{subfield.code}"
          xml << "    <subfield code=\"#{attribute(subfield.code, at)}\">#{text(subfield.value, at)}</subfield>\n"
        end
        xml << "  </datafield>\n"
      end

      def text(value, where) = escape(value, where, /[&<>\r]/, TEXT)

      def attribute(value, where) = escape(value, where, /[&<>"\r\t\n]/, ATTRIBUTE)

      # nil is written as "". Raises SerializeError for invalid UTF-8 and
      # for characters XML 1.0 cannot represent.
      def escape(value, where, pattern, table)
        string = value.to_s
        string = string.dup.force_encoding(Encoding::UTF_8) unless string.encoding == Encoding::UTF_8
        raise SerializeError, "#{where}: invalid UTF-8 #{string.inspect}" unless string.valid_encoding?

        forbidden = string[FORBIDDEN]
        raise SerializeError, "#{where}: #{forbidden.inspect} cannot be represented in XML 1.0" if forbidden

        string.gsub(pattern, table)
      end

    end
  end
end
