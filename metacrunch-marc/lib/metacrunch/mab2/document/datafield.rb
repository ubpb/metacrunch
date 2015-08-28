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
          @subfields = {}
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
            @subfields.values.map(&:to_a).flatten(1)
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

        # ------------------------------------------------------------------------------
        # Serialization
        # ------------------------------------------------------------------------------

        def to_xml(builder)
          builder.datafield(tag: tag, ind1: ind1, ind2: ind2) do
            @subfields.values.each do |_subfield_set|
              _subfield_set.to_xml(builder)
            end
          end
        end

      end
    end
  end
end
