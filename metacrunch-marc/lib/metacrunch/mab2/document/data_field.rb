module Metacrunch
  module Mab2
    class Document
      class DataField

        attr_reader :name
        attr_reader :ind1, :ind2

        def initialize(name, ind1:nil, ind2:nil)
          raise ArgumentError, "required DataField#name not given" if name.nil?

          @name       = name
          @ind1       = ind1
          @ind2       = ind2
        end

        def matches?(ind1: nil, ind2: nil)
          (ind1.nil? or @ind1 == ind1) and (ind2.nil? or @ind2 == ind2)
        end

        # ------------------------------------------------------------------------------
        # Sub fields
        # ------------------------------------------------------------------------------

        #
        # @return [Hash{String => Metacrunch::Mab2::Document::DataField::SubField::Set}]
        # @private
        #
        def sub_fields_struct
          @sub_fields_struct ||= {}
        end
        private :sub_fields_struct

        #
        # @return [Array<Metacrunch::Mab2::Document::DataField::SubField::Set>]
        #
        def all_sub_fields
          sub_fields_struct.values
        end

        #
        # Returns the sub field matching the given name.
        #
        # @param [String] name of the sub field
        # @return [Metacrunch::Mab2::Document::DataField::SubField::Set] sub field with the given name. The set
        #  is empty if the sub field doesn't exists.
        #
        def sub_fields(name)
          sub_fields_struct[name] || SubField::Set.new
        end

        #
        # Adds a new sub field.
        #
        # @param [Metacrunch::Mab2::Document::DataField::SubField] sub_field
        #
        def add_sub_field(sub_field)
          sub_field_set  = sub_fields_struct[sub_field.name] ||= SubField::Set.new
          sub_field_set << sub_field

          sub_fields_struct[sub_field.name] = sub_field_set
        end

      end
    end
  end
end
