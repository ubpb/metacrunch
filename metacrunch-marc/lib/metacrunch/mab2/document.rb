module Metacrunch
  module Mab2
    class Document
      require_relative "document/mab_xml_parser"
      require_relative "document/controlfield"
      require_relative "document/datafield"
      require_relative "document/datafield_set"
      require_relative "document/subfield"
      require_relative "document/subfield_set"

      # ------------------------------------------------------------------------------
      # Parsing
      # ------------------------------------------------------------------------------

      #
      # @param [String] xml repesenting a MAB document in Aleph MAB XML format
      # @return [Metacrunch::Mab2::Document]
      #
      def self.from_mab_xml(xml)
        MabXmlParser.new.parse(xml)
      end

      def initialize
        @controlfields = {}
        @datafields = {}
      end

      # ------------------------------------------------------------------------------
      # Control fields
      # ------------------------------------------------------------------------------

      #
      # Returns the control field matching the given tag.
      #
      # @param [String] tag of the control field
      # @return [Controlfield] control field with the given tag.
      #
      def controlfield(tag)
        @controlfields[tag] || Controlfield.new(tag)
      end

      #
      # Adds a new control field.
      #
      # @param [Metacrunch::Mab2::Document::Controlfield] controlfield
      #
      def add_controlfield(controlfield)
        @controlfields[controlfield.tag] = controlfield
      end

      # ------------------------------------------------------------------------------
      # Data fields
      # ------------------------------------------------------------------------------

      #
      # Returns the data fields matching the given tag and ind1/ind2.
      #
      # @param [String, nil] tag of the data field. Can be nil to match any data field.
      # @param [String, nil] ind1 filter for ind1. Can be nil to match any indicator 1.
      # @param [String, nil] ind2 filter for ind2. Can be nil to match any indicator 2.
      # @return [Metacrunch::Mab2::Document::DatafieldSet] data field with the given tag and ind1/ind2.
      #  The set is empty if a matching field with the tag and/or ind1/ind2 doesn't exists.
      #
      def datafields(tag = nil, ind1: nil, ind2: nil)
        if tag.nil?
          DatafieldSet.new(@datafields.values.flatten(1))
        else
          set = DatafieldSet.new(@datafields[tag] || [])
          return set if set.empty? || (ind1.nil? && ind2.nil?)

          ind1 = map_indicator(ind1)
          ind2 = map_indicator(ind2)

          set.select do |_datafield|
            check_indicator(ind1, _datafield.ind1) && check_indicator(ind2, _datafield.ind2)
          end
        end
      end

      #
      # Adds a new data field.
      #
      # @param [Metacrunch::Mab2::Document::Datafield] datafield
      #
      def add_datafield(datafield)
        (@datafields[datafield.tag] ||= []) << datafield
      end

    private

      def map_indicator(ind)
        ind.is_a?(Array) ? ind.map { |_el| _el == :blank ? [" ", "-", nil] : _el }.flatten(1) : ind
      end

      def check_indicator(requested_ind, datafield_ind)
        if !requested_ind
          true
        elsif requested_ind == :blank && (datafield_ind == " " || datafield_ind == "-" || datafield_ind.nil?)
          true
        elsif requested_ind == datafield_ind
          true
        elsif requested_ind.is_a?(Array) && requested_ind.include?(datafield_ind)
          true
        else
          false
        end
      end

    end
  end
end
