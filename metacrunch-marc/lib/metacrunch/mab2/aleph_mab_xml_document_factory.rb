module Metacrunch
  module Mab2
    class AlephMabXmlDocumentFactory

      def initialize(aleph_mab_xml)
        @aleph_mab_xml = aleph_mab_xml
      end

      def to_document
        @document ||= document_from_xml(@aleph_mab_xml)
      end

    private

      def document_from_xml(aleph_mab_xml)
        oxdoc    = Ox.parse(aleph_mab_xml)
        document = Document.new

        oxdoc.locate("OAI-PMH/ListRecords/record/metadata/record/*").each do |oxnode|
          case oxnode.name
          when "controlfield" then add_control_field(document, oxnode)
          when "datafield"    then add_data_field(document, oxnode)
          end
        end

        document
      end

      def add_control_field(document, oxnode)
        name          = oxnode["tag"]
        values        = oxnode.text
        control_field = Document::ControlField.new(name, values)

        document.add_control_field(control_field)
      end

      def add_data_field(document, node)
        name       = node["tag"]
        ind1       = node["ind1"]
        ind2       = node["ind2"]
        data_field = Document::DataField.new(name, ind1: ind1, ind2: ind2)

        node.locate("subfield").each do |sub_node|
          add_sub_field(data_field, sub_node)
        end

        document.add_data_field(data_field)
      end

      def add_sub_field(data_field, node)
        name      = node["code"]
        value     = html_entities_coder.decode(node.text)
        sub_field = Document::DataField::SubField.new(name, value)

        data_field.add_sub_field(sub_field)
      end

      def html_entities_coder
        @html_entities_coder ||= HTMLEntities.new
      end

    end
  end
end
