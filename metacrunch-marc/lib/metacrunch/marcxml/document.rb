require_relative "document/controlfield"
require_relative "document/datafield"
require_relative "document/datafield_set"
require_relative "document/subfield"
require_relative "document/subfield_set"

module Metacrunch
  module Marcxml
    class Document

      def initialize
        @controlfields_map = {}
        @datafields_map    = {}
      end

      def empty?
        @controlfields_map.blank? && @datafields_map.blank?
      end

      # ------------------------------------------------------------------------------
      # Control fields
      # ------------------------------------------------------------------------------

      #
      # Returns the control field matching the given tag or nil if a control field
      # with the given tag does not exist.
      #
      # @param tag [String, Integer] the tag of the control field. The tag can be
      #   a string or an integer.
      # @return [Metacrunch::Marcxml::Document::Controlfield, nil] the control field with the matching tag or nil
      #   if a control field with a matching tag does not exist.
      #
      def controlfield(tag)
        @controlfields_map[normalize_tag(tag)]
      end

      #
      # @!visibility private
      #
      def add_controlfield(controlfield)
        @controlfields_map[controlfield.tag] = controlfield
      end

      # ------------------------------------------------------------------------------
      # Data fields
      # ------------------------------------------------------------------------------

      #
      # Returns the data fields matching the given tag(s) and/or ind1/ind2.
      #
      # @param tag [String, Integer, #each, nil] filter by tag(s). Can be `nil`
      #   to match all data fields. The tag can be a string or an integer. To filter for
      #   more than a single tag, `tag` also accepts any object that responds to `#each` like
      #   `Array` and `Range`.
      # @param ind1 [nil, String, Array<String>] filter by indicator 1. Can be nil to match
      #   any indicator.
      # @param ind2 [nil, String, Array<String>] filter by indicator 2. Can be nil to match
      #   any indicator.
      #
      # @return [Metacrunch::Marcxml::Document::DatafieldSet] Set of data fields matching the
      #  given tag(s) and ind1/ind2. The set is empty if a matching field doesn't exist.
      #
      def datafields(tag = nil, ind1: nil, ind2: nil)
        matched_datafields = if tag.nil?
          @datafields_map.values.flatten(1)
        elsif tag.is_a?(Enumerable)
          tag.map{ |_tag| @datafields_map[normalize_tag(_tag)] }.compact.flatten(1)
        else
          @datafields_map[normalize_tag(tag)]
        end

        matched_datafields = (matched_datafields || []).select do |datafield|
          match_indicator(ind1, datafield.ind1) && match_indicator(ind2, datafield.ind2)
        end

        DatafieldSet.new(matched_datafields)
      end

      #
      # @!visibility private
      #
      def add_datafield(datafield)
        (@datafields_map[datafield.tag] ||= []) << datafield
        datafield
      end

      # ------------------------------------------------------------------------------
      # Query API
      # ------------------------------------------------------------------------------

      #
      # Returns a control field value or data field/sub field values matching the
      # given query string.
      #
      # @param query_string [String] a query string.
      #
      # @return [Array<String>] The sub field values matching the query. Is empty if no match
      #  is found.
      #
      def [](query_string)
        # Control field query
        if query_string.starts_with?("00")
          # Example: "005"
          # [0..2] => Control field tag
          tag = query_string[0..2].presence
          controlfield(tag)&.value

        # Data field / sub field query
        else
          # Example: "100**a,e"
          # [0..2] => Data field tag (required).
          # [3]    => Ind1, defaults to `*`, which matches any indicator 1 (optional). ` `, `-` or `_` will be interpreted as `blank`.
          # [4]    => Ind2, defaults to `*`, which matches any indicator 2 (optional). ` `, `-` or `_` will be interpreted as `blank`.
          # [5]    => Sub field code(s) (optional).
          tag      = query_string[0..2].presence

          ind1     = query_string[3].presence
          ind1     = nil    if ind1 == "*"
          ind1     = :blank if ind1 == "-" || ind1 == "_" || ind1 == " "

          ind2     = query_string[4].presence
          ind2     = nil    if ind2 == "*"
          ind2     = :blank if ind2 == "-" || ind2 == "_" || ind2 == " "

          subfield_codes = query_string[5..-1]&.split(",")&.map(&:strip).compact.presence

          datafields(tag, ind1: ind1, ind2: ind2).subfields(subfield_codes).values
        end
      end

    private

      def match_indicator(requested_ind, datafield_ind)
        [*[requested_ind]].flatten.map do |_requested_ind|
          if !_requested_ind
            true
          elsif _requested_ind == :blank && (datafield_ind == " " || datafield_ind == "-" || datafield_ind == "_" || datafield_ind.nil?)
            true
          elsif _requested_ind == datafield_ind
            true
          else
            false
          end
        end.any?
      end

      def normalize_tag(tag)
        case tag
        when Integer then tag.to_s.rjust(3, "0")
        when String  then tag[0..2]
        else tag.to_s[0..2]
        end
      end

    end
  end
end
