module Metacrunch
  module Mab2
    class Document
      class Datafield

        attr_reader :tag
        attr_reader :ind1, :ind2

        def initialize(tag, ind1:nil, ind2:nil)
          raise ArgumentError, "required Datafield#tag not given" if tag.nil?

          @tag  = tag
          @ind1 = ind1
          @ind2 = ind2
        end

        def matches?(ind1: nil, ind2: nil)
          (ind1.nil? or @ind1 == ind1) and (ind2.nil? or @ind2 == ind2)
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
        # @return [Array<Metacrunch::Mab2::Document::Datafield::Subfield::Set>]
        #
        def all_subfields
          subfields_struct.values
        end

        #
        # Returns the sub field matching the given tag.
        #
        # @param [String] tag of the sub field
        # @return [Metacrunch::Mab2::Document::Datafield::Subfield::Set] sub field with the given tag. The set
        #  is empty if the sub field doesn't exists.
        #
        def subfields(tag)
          subfields_struct[tag] || Subfield::Set.new
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
