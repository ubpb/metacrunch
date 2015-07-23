module Metacrunch
  module Mab2
    class Document
      require_relative "./document/controlfield"
      require_relative "./document/datafield"
      require_relative "./document/datafield_set"
      require_relative "./document/subfield"
      require_relative "./document/subfield_set"

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
      # @return [Hash{String => Metacrunch::Mab2::Document::Controlfield}]
      # @private
      #
      def controlfields_struct
        @controlfields_struct ||= {}
      end
      private :controlfields_struct

      #
      # Returns the control field matching the given tag.
      #
      # @param [String] tag of the control field
      # @return [Controlfield] control field with the given tag.
      #
      def controlfield(tag)
        controlfields_struct[tag] || Controlfield.new(tag)
      end

      #
      # Adds a new control field.
      #
      # @param [Metacrunch::Mab2::Document::Controlfield] controlfield
      #
      def add_controlfield(controlfield)
        controlfields_struct[controlfield.tag] = controlfield
      end

      # ------------------------------------------------------------------------------
      # Data fields
      # ------------------------------------------------------------------------------

      #
      # @return [Hash{String => Metacrunch::Mab2::Document::Datafield::Set}]
      # @private
      #
      def datafields_struct
        @datafields_struct ||= {}
      end
      private :datafields_struct

      #
      # Returns the data fields matching the given tag and ind1/ind2.
      #
      # @param [String] tag of the data field
      # @param [String, nil] ind1 filter for ind1. Can be nil to match any.
      # @param [String, nil] ind2 filter for ind2. Can be nil to match any.
      # @return [Metacrunch::Mab2::Document::Datafield::Set] data field with the given tag and ind1/ind2.
      #  The set is empty if a matching field with the tag and/or ind1/ind2 doesn't exists.
      #
      def datafields(tag, ind1: nil, ind2: nil)
        set = datafields_struct[tag] || Datafield::Set.new
        return set if set.empty?

        if ind1 || ind2
          filtered_datafields = set.select do |datafield|
            (!ind1 || (ind1 == :blank ? datafield.ind1 == " " || datafield.ind1 == "-" : datafield.ind1 == ind1)) &&
            (!ind2 || (ind2 == :blank ? datafield.ind2 == " " || datafield.ind2 == "-" : datafield.ind2 == ind2))
          end

          Datafield::Set.new(filtered_datafields)
        else
          set
        end
      end

      #
      # Adds a new data field.
      #
      # @param [Metacrunch::Mab2::Document::Datafield] datafield
      #
      def add_datafield(datafield)
        datafield_set  = datafields(datafield.tag)
        datafield_set << datafield

        datafields_struct[datafield.tag] = datafield_set
      end

      # ------------------------------------------------------------------------------
      # Serialization
      # ------------------------------------------------------------------------------

      def to_xml
        builder = ::Builder::XmlMarkup.new(indent: 2)
        builder.instruct!(:xml, :encoding => "UTF-8")
        builder.mab_xml do
          controlfields_struct.values.each do |_controlfield|
            _controlfield.to_xml(builder)
          end

          datafields_struct.values.each do |_datafield_set|
            _datafield_set.to_xml(builder)
          end
        end
      end

    end
  end
end
