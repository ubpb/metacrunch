require_relative "./document/control_field"
require_relative "./document/data_field"
require_relative "./document/data_field_set"
require_relative "./document/sub_field"
require_relative "./document/sub_field_set"

module Metacrunch
  module Mab2
    class Document

      # ------------------------------------------------------------------------------
      # Parsing
      # ------------------------------------------------------------------------------

      #
      # @param [String] xml repesenting a MAB document in Aleph MAB XML format
      # @return [Metacrunch::Mab2::Document]
      #
      def self.from_aleph_mab_xml(xml)
        AlephMabXmlDocumentFactory.new(xml).to_document
      end

      # ------------------------------------------------------------------------------
      # Control fields
      # ------------------------------------------------------------------------------

      #
      # @return [Hash{String => Metacrunch::Mab2::Document::ControlField}]
      # @private
      #
      def control_fields_struct
        @control_fields_struct ||= {}
      end
      private :control_fields_struct

      #
      # @return [Array<Metacrunch::Mab2::Document::ControlField>]
      #
      def all_control_fields
        control_fields_struct.values
      end

      #
      # Returns the control field matching the given name.
      #
      # @param [String] name of the control field
      # @return [ControlField, nil] control field with the given name. Is nil
      #  if the control field doesn't exists.
      #
      def control_field(name)
        control_fields_struct[name]
      end

      #
      # Adds a new control field.
      #
      # @param [Metacrunch::Mab2::Document::ControlField] control_field
      #
      def add_control_field(control_field)
        control_fields_struct[control_field.name] = control_field
      end

      # ------------------------------------------------------------------------------
      # Data fields
      # ------------------------------------------------------------------------------

      #
      # @return [Hash{String => Metacrunch::Mab2::Document::DataField::Set}]
      # @private
      #
      def data_fields_struct
        @data_fields_struct ||= {}
      end
      private :data_fields_struct

      #
      # @return [Array<Metacrunch::Mab2::Document::DataField>]
      #
      def all_data_fields
        data_fields_struct.values
      end

      #
      # Returns the data field matching the given name.
      #
      # @param [String] name of the data field
      # @return [Metacrunch::Mab2::Document::DataField::Set] data field with the given name. The set
      #  is empty if the data field doesn't exists.
      #
      def data_fields(name)
        data_fields_struct[name] || DataField::Set.new
      end

      #
      # Adds a new data field.
      #
      # @param [Metacrunch::Mab2::Document::DataField] data_field
      #
      def add_data_field(data_field)
        data_field_set  = data_fields_struct[data_field.name] ||= DataField::Set.new
        data_field_set << data_field

        data_fields_struct[data_field.name] = data_field_set
      end

      # ------------------------------------------------------------------------------
      # Query
      # ------------------------------------------------------------------------------

      def values(data_field:, ind1:nil, ind2:nil, sub_field:)
        data_fields(data_field).filter(ind1: ind1, ind2: ind2).sub_fields(sub_field).values
      end

    end
  end
end
