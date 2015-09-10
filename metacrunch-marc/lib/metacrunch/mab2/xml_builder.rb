require "nokogiri"
require_relative "../mab2"

class Metacrunch::Mab2::XmlBuilder
  def initialize(identifier = nil, &block)
    @builder =
    Nokogiri::XML::Builder.new do
      send(
        :"OAI-PMH",
        "xmlns" => "http://www.openarchives.org/OAI/2.0/",
        "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:schemaLocation" => "http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd"
      ) do
        ListRecords do
          record do
            if identifier
              header do |_xml|
                _xml.identifier identifier
              end
            end

            metadata do
              record("xmlns" => "http://www.ddb.de/professionell/mabxml/mabxml-1.xsd") do
                define_singleton_method(:controlfield) do |_tag, _text|
                  send(:method_missing, :controlfield, _text, tag: _tag)
                end

                define_singleton_method(:datafield) do |_tag, _attributes = {}, &_block|
                  send(:method_missing, :datafield, {tag: _tag}.merge(_attributes), &_block)
                end

                define_singleton_method(:subfield) do |_code, _text|
                  send(:method_missing, :subfield, _text, code: _code)
                end

                instance_eval(&block)
              end
            end
          end
        end
      end
    end
  end

  def to_xml
    @builder.to_xml
  end
end
