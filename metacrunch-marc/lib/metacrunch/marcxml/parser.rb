module Metacrunch
  module Marcxml
    class Parser < Ox::Sax
      class ParsingDone < StandardError ; end

      def parse(marc_xml, collection_mode: false)
        @stack   = []
        @records = []
        @collection_mode = collection_mode

        begin
          Ox.sax_parse(self, marc_xml, convert_special: true)
        rescue ParsingDone ; end

        collection_mode ? @records : @records.first
      end

      def start_element(name)
        @stack << [name, {}]

        element_name, element_data = @stack[-1]
        parent_name, parent_data   = @stack[-2]

        if element_name == :record
          element_data[:record] = Record.new
        elsif element_name == :leader && parent_name == :record
          element_data[:leader] = Record::Leader.new
        elsif element_name == :controlfield && parent_name == :record
          element_data[:controlfield] = Record::Controlfield.new
        elsif element_name == :datafield && parent_name == :record
          element_data[:datafield] = Record::Datafield.new
        elsif element_name == :subfield && parent_name == :datafield
          element_data[:subfield] = Record::Subfield.new
        end
      end

      def end_element(name)
        element_name, element_data = @stack[-1]
        parent_name, parent_data   = @stack[-2]

        if element_name == :record
          @records << element_data[:record] unless element_data[:record].empty?
          raise ParsingDone unless @collection_mode
        elsif element_name == :leader && parent_name == :record
          parent_data[:record].set_leader(element_data[:leader])
        elsif element_name == :controlfield && parent_name == :record
          parent_data[:record].add_controlfield(element_data[:controlfield])
        elsif element_name == :datafield && parent_name == :record
          parent_data[:record].add_datafield(element_data[:datafield])
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

        if element_name == :leader && parent_name == :record
          element_data[:leader].value = value
        elsif element_name == :controlfield && parent_name == :record
          element_data[:controlfield].value = value
        elsif element_name == :subfield && parent_name == :datafield
          element_data[:subfield].value = value
        end
      end
    end
  end
end
