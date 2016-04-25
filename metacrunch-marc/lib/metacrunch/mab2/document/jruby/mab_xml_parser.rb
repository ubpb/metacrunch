module Metacrunch
  module Mab2
    class Document
      class MabXmlParser

        def parse(mab_xml)
          xml = Nokogiri::XML(mab_xml.try(:strip))
          xml.remove_namespaces!

          html_entities = HTMLEntities.new
          document = Document.new

          xml.xpath("//metadata/record").children.each do |node|
            if node.name == "controlfield"
              controlfield = Metacrunch::Mab2::Document::Controlfield.new
              controlfield.tag = node.attributes["tag"].value
              controlfield.values = node.content
              document.add_controlfield(controlfield)
            elsif node.name == "datafield" then
              datafield = Metacrunch::Mab2::Document::Datafield.new
              datafield.tag = node.attributes["tag"].value
              datafield.ind1 = node.attributes["ind1"].try(:value)
              datafield.ind2 = node.attributes["ind2"].try(:value)

              node.children.each do |subnode|
                if subnode.name == "subfield"
                  subfield = Metacrunch::Mab2::Document::Subfield.new
                  subfield.code = subnode.attributes["code"].value
                  value = subnode.content
                  subfield.value = value.include?("&") ? html_entities.decode(value) : value
                  datafield.add_subfield(subfield)
                end
              end

              document.add_datafield(datafield)
            end
          end

          document
        end

      end
    end
  end
end
