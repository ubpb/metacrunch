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
          @subfields = {}
        end

        def value
          subfields.value
        end

        # ------------------------------------------------------------------------------
        # Sub fields
        # ------------------------------------------------------------------------------

        #
        # Returns the sub field matching the given code.
        #
        # @param [String] code of the sub field
        # @return [Metacrunch::Mab2::Document::SubfieldSet] sub field with the given code. The set
        #  is empty if the sub field doesn't exists.
        #
        def subfields(code = nil)
          result =  Metacrunch::Mab2::Document::SubfieldSet.new

          if code.nil?
            result.concat(@subfields.values.flatten(1))
          elsif _subfields = @subfields[code]
            result.concat(_subfields)
          elsif (codes = code).is_a?(Array)
            result.concat(codes.map { |_code| @subfields[_code] }.compact.flatten(1))
          end

          result
        end

        #
        # Adds a new sub field.
        #
        # @param [Metacrunch::Mab2::Document::Subfield] subfield
        #
        def add_subfield(subfield)
          (@subfields[subfield.code] ||= []) << subfield
        end

      end
    end
  end
end
