module Metacrunch
  module Mab2
    class Document
      class Datafield

        attr_reader :tag
        attr_reader :ind1, :ind2

        def initialize(tag, ind1:nil, ind2:nil)
          @tag  = tag
          @ind1 = ind1
          @ind2 = ind2
          @subfields_map = {}
        end

        #
        # Returns the sub fields matching the given code.
        #
        # @param [String, nil, Array<String>] code of the sub field
        # @return [Metacrunch::Mab2::Document::SubfieldSet] sub field with the given code. The set
        #  is empty if the sub field doesn't exists.
        #
        def subfields(code = nil)
          matched_subfields = if code.nil?
            @subfields_map.values.flatten(1)
          else
            if (codes = code).is_a?(Array)
              codes.map{ |_code| @subfields_map[_code] }.compact.flatten(1)
            else
              @subfields_map[code]
            end
          end

          SubfieldSet.new(matched_subfields)
        end

        #
        # Adds a new sub field.
        #
        # @param [Metacrunch::Mab2::Document::Subfield] subfield
        #
        def add_subfield(subfield)
          (@subfields_map[subfield.code] ||= []) << subfield
          subfield
        end

      end
    end
  end
end
