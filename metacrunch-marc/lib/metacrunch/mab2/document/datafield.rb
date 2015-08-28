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

        # ------------------------------------------------------------------------------
        # Sub fields
        # ------------------------------------------------------------------------------

        #
        # @return [Hash{String => Metacrunch::Mab2::Document::SubfieldSet}]
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
        # @return [Metacrunch::Mab2::Document::SubfieldSet] sub field with the given code. The set
        #  is empty if the sub field doesn't exists.
        #
        def subfields(code = nil)
          if code.nil?
            @subfields_struct.values.map(&:to_a).flatten(1)
          else
            subfields_struct[code]
          end ||
          Metacrunch::Mab2::Document::SubfieldSet.new
        end

        #
        # Adds a new sub field.
        #
        # @param [Metacrunch::Mab2::Document::Subfield] subfield
        #
        def add_subfield(subfield)
          subfield_set  = subfields(subfield.code)
          subfield_set << subfield

          subfields_struct[subfield.code] = subfield_set
        end

        # ------------------------------------------------------------------------------
        # Serialization
        # ------------------------------------------------------------------------------

        def to_xml(builder)
          builder.datafield(tag: tag, ind1: ind1, ind2: ind2) do
            subfields_struct.values.each do |_subfield_set|
              _subfield_set.to_xml(builder)
            end
          end
        end

      end
    end
  end
end
