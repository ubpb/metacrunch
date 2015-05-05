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
          when "controlfield" then add_controlfield(document, oxnode)
          when "datafield"    then add_datafield(document, oxnode)
          end
        end

        document
      end

      def add_controlfield(document, oxnode)
        tag          = oxnode["tag"]
        values       = oxnode.text
        controlfield = Document::Controlfield.new(tag, values)

        document.add_controlfield(controlfield)
      end

      def add_datafield(document, node)
        tag        = node["tag"]
        ind1       = node["ind1"]
        ind2       = node["ind2"]
        datafield  = Document::Datafield.new(tag, ind1: ind1, ind2: ind2)

        node.locate("subfield").each do |sub_node|
          add_subfield(datafield, sub_node)
        end

        document.add_datafield(datafield)
      end

      def add_subfield(datafield, node)
        code      = node["code"]
        value     = html_entities_coder.decode(node.text)
        subfield  = Document::Datafield::Subfield.new(code, value)

        datafield.add_subfield(subfield)
      end

      def html_entities_coder
        @html_entities_coder ||= HTMLEntities.new
      end

    end
  end
end
