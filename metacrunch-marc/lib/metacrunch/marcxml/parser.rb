module Metacrunch
  module Marcxml
    class Parser < Ox::Sax
      class ParsingDone < StandardError ; end

      def parse(marc_xml, collection_mode: false)
        @stack     = []
        @documents = []
        @collection_mode = collection_mode

        begin
          Ox.sax_parse(self, marc_xml, convert_special: true)
        rescue ParsingDone ; end

        collection_mode ? @documents : @documents.first
      end

      def start_element(name)
        @stack << [name, {}]

        element_name, element_data = @stack[-1]
        parent_name, parent_data   = @stack[-2]

        if element_name == :record
          element_data[:document] = Document.new
        elsif element_name == :controlfield && parent_name == :record
          element_data[:controlfield] = Document::Controlfield.new
        elsif element_name == :datafield && parent_name == :record
          element_data[:datafield] = Document::Datafield.new
        elsif element_name == :subfield && parent_name == :datafield
          element_data[:subfield] = Document::Subfield.new
        end
      end

      def end_element(name)
        element_name, element_data = @stack[-1]
        parent_name, parent_data   = @stack[-2]

        if element_name == :record
          @documents << element_data[:document] unless element_data[:document].empty?
          raise ParsingDone unless @collection_mode
        elsif element_name == :controlfield && parent_name == :record
          parent_data[:document].add_controlfield(element_data[:controlfield])
        elsif element_name == :datafield && parent_name == :record
          parent_data[:document].add_datafield(element_data[:datafield])
        elsif element_name == :subfield && parent_name == :datafield
          parent_data[:datafield].add_subfield(element_data[:subfield])
        end

        @stack.pop
      end

      def attr(name, value)
        element_name, element_data = @stack[-1]
        parent_name, parent_data   = @stack[-2]

        if element_name == :controlfield && parent_name == :record
          element_data[:controlfield].tag = value if name == :tag
        elsif element_name == :datafield && parent_name == :record
          element_data[:datafield].tag  = value if name == :tag
          element_data[:datafield].ind1 = value if name == :ind1
          element_data[:datafield].ind2 = value if name == :ind2
        elsif element_name == :subfield && parent_name == :datafield
          element_data[:subfield].code = value if name == :code
        end
      end

      def text(value)
        element_name, element_data = @stack[-1]
        parent_name, parent_data   = @stack[-2]

        if element_name == :controlfield && parent_name == :record
          element_data[:controlfield].value = value
        elsif element_name == :subfield && parent_name == :datafield
          element_data[:subfield].value = value
        end
      end
    end
  end
end
