module Metacrunch
  class SNR
    class Section

      attr_reader :name

      def initialize(name)
        raise ArgumentError, "required Section#name not given" if name.nil?

        @name   = name
        @fields = []
      end

      # ------------------------------------------------------------------------------
      # Common API
      # ------------------------------------------------------------------------------

      #
      # Adds a field
      #
      def add(field_name, value)
        add_field(Field.new(field_name, value))
      end

      # ------------------------------------------------------------------------------
      # Fields
      # ------------------------------------------------------------------------------

      #
      # Return all fields.
      #
      # @return [Array<Metacrunch::SNR::Section::Field>]
      #
      def fields
        @fields
      end

      #
      # Adds a new field to this section.
      #
      # @param [Metacrunch::SNR::Section::Field] field
      # @return [Metacrunch::SNR::Section::Field]
      #
      def add_field(field)
        @fields << field
        field
      end

    end
  end
end
