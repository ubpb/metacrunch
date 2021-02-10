module Metacrunch
  module Marcxml
    class Record
      class Datafield

        attr_accessor :tag
        attr_accessor :ind1, :ind2

        def initialize(tag = nil, ind1:nil, ind2:nil)
          @tag  = tag
          @ind1 = ind1
          @ind2 = ind2
          @subfields_map = {}
        end

        #
        # Returns the sub fields matching the given code.
        #
        # @param [String, nil, Array<String>] code of the sub field
        # @return [Array<Metacrunch::Marcxml::Record::Subfield>] list of sub fields with
        #   the given code. The list is empty if the sub field doesn't exists.
        #
        def subfields(code = nil)
          matched_subfields = if code.nil?
            @subfields_map.values.flatten(1)
          else
            if (codes = code).is_a?(Array)
              codes.map{ |c| @subfields_map[c] }.compact.flatten(1)
            else
              @subfields_map[code]
            end
          end

          matched_subfields || []
        end

        #
        # Adds a new sub field.
        #
        # @param [Metacrunch::Marcxml::Record::Subfield] subfield
        #
        def add_subfield(subfield)
          (@subfields_map[subfield.code] ||= []) << subfield
          self
        end

      end
    end
  end
end
