module Metacrunch
  module Mab2
    class Document
      class Datafield

        attr_accessor :tag
        attr_accessor :ind1, :ind2

        def initialize(tag = nil, ind1:nil, ind2:nil)
          @tag  = tag
          @ind1 = ind1
          @ind2 = ind2
        end

        def matches?(ind1: nil, ind2: nil)
          (ind1.nil? || @ind1 == ind1) && (ind2.nil? || @ind2 == ind2)
        end

        # ------------------------------------------------------------------------------
        # Sub fields
        # ------------------------------------------------------------------------------

        #
        # @return [Hash{String => Metacrunch::Mab2::Document::Datafield::Subfield::Set}]
        # @private
        #
        def subfields_struct
          @subfields_struct ||= {}
        end
        private :subfields_struct

        #
        # Returns the sub field matching the given code.
        #
        # @param [String] code of the sub field
        # @return [Metacrunch::Mab2::Document::Datafield::Subfield::Set] sub field with the given code. The set
        #  is empty if the sub field doesn't exists.
        #
        def subfields(code)
          subfields_struct[code] || Subfield::Set.new
        end

        #
        # Adds a new sub field.
        #
        # @param [Metacrunch::Mab2::Document::Datafield::Subfield] subfield
        #
        def add_subfield(subfield)
          subfield_set  = subfields(subfield.code)
          subfield_set << subfield

          subfields_struct[subfield.code] = subfield_set
        end

      end
    end
  end
end
