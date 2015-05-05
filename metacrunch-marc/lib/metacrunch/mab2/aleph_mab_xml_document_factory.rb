require "htmlentities"
require "ox"
require_relative "./document"

module Metacrunch
  module Mab2
    class AlephMabXmlDocumentFactory

      def initialize(aleph_mab_xml)
        @aleph_mab_xml = aleph_mab_xml
      end

      def to_document
        @document ||= Parser.new.parse(@aleph_mab_xml)
      end

    private

      class Parser < Ox::Sax
        def parse(io_or_string)
          # initialize state machine
          @in_controlfield = @in_datafield = @in_subfield = false

          @controlfield = @datafield = @subfield = nil
          @document = Document.new
          @html_entities_coder = HTMLEntities.new

          io = io_or_string.is_a?(IO) ? io_or_string : StringIO.new(io_or_string)

          # convert_special tells ox to convert some html entities already during
          # parsing, which minifies the amount of entities we have to decode ourself
          Ox.sax_parse(self, io, convert_special: true)

          return @document
        end

        def start_element(name)
          if name == :subfield
            @in_subfield = true
            @subfield = Document::Datafield::Subfield.new
          elsif name == :datafield
            @in_datafield = true
            @datafield = Document::Datafield.new
          elsif name == :controlfield
            @in_controlfield = true
            @controlfield = Document::Controlfield.new
          end
        end

        def end_element(name)
          if @in_subfield
            @in_subfield = false
            @datafield.add_subfield(@subfield)
          elsif @in_datafield
            @in_datafield = false
            @document.add_datafield(@datafield)
          elsif @in_controlfield
            @in_controlfield = false
            @document.add_controlfield(@controlfield)
          end
        end

        def attr(name, value)
          if @in_subfield
            @subfield.code = value if name == :code
          elsif @in_datafield
            if name == :tag
              @datafield.tag = value
            elsif name == :ind1
              @datafield.ind1 = value
            elsif name == :ind2
              @datafield.ind2 = value
            end
          elsif @in_controlfield
            @controlfield.tag = value if name == :tag
          end
        end

        def text(value)
          if @in_subfield
            @subfield.value = value.include?("&") ? @html_entities_coder.decode(value) : value
          elsif @in_controlfield
            @controlfield.values = value
          end
        end
      end
    end
  end
end
