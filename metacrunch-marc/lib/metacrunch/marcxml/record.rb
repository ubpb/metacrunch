require_relative "record/leader"
require_relative "record/controlfield"
require_relative "record/datafield"
require_relative "record/datafield_set"
require_relative "record/subfield"
require_relative "record/subfield_set"

module Metacrunch
  module Marcxml
    class Record

      def initialize
        @controlfields_map = {}
        @datafields_map    = {}
        @leader            = nil
      end

      def empty?
        @leader.blank? && @controlfields_map.blank? && @datafields_map.blank?
      end

      # ------------------------------------------------------------------------------
      # Leader
      # ------------------------------------------------------------------------------

      def leader
        @leader
      end

      def set_leader(leader)
        @leader = leader
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
      # @return [Metacrunch::Marcxml::Record::Controlfield, nil] the control field with the matching tag or nil
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
      # @return [Metacrunch::Marcxml::Record::DatafieldSet] Set of data fields matching the
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
      # given query string. *THE FEATURE IS EXPERIMENTAL AND SUBJECT TO CHANGE*
      #
      # @param query_string [String] a query string. Each query string starts with
      #   three letters for the tag. If the tag starts with `00` it is considered a
      #   query for a control field value. Otherwise it is considered a data field /
      #   sub field query. In that case the next two characters are used to match ind1
      #   and ind2. The default value is `*` which matches every indicator value.
      #  `#`, `-`, and `_` are interpreted as `blank`. The last characters are used to
      #   match the code of the sub fields. To query for more than one sub field code
      #   you may separate them using commas.
      #
      # @param flatten_subfields [Boolean] TODO
      #
      # @param values_as_hash [Boolean] TODO
      #
      # @return [Array<String>, String, nil] in case for a control field query it return
      #   the value or `nil` if the control field doesn't exists. In case for a data field
      #   / sub field query it returns the matching values.
      #
      def [](query_string, flatten_subfields: true, values_as_hash: false)
        #
        # Control field query
        #
        if query_string.starts_with?("00")
          # Example: "005"
          # [0..2] => Control field tag
          tag = query_string[0..2].presence
          controlfield = controlfield(tag)

          if controlfield
            values_as_hash ? controlfield.to_h : controlfield.value
          end
        #
        # Data field / sub field query
        #
        else
          # Example: "100**a,e"
          # [0..2] => Data field tag (required).
          # [3]    => Ind1, defaults to `*`, which matches any indicator 1 (optional). `#`, `-` or `_` will be interpreted as `blank`.
          # [4]    => Ind2, defaults to `*`, which matches any indicator 2 (optional). `#`, `-` or `_` will be interpreted as `blank`.
          # [5]    => Sub field code(s) (optional).
          tag      = query_string[0..2].presence

          ind1     = query_string[3].presence
          ind1     = nil    if ind1 == "*"
          ind1     = :blank if ind1 == "#" || ind1 == "-" || ind1 == "_"

          ind2     = query_string[4].presence
          ind2     = nil    if ind2 == "*"
          ind2     = :blank if ind2 == "#" || ind2 == "-" || ind2 == "_"

          subfield_codes = query_string[5..-1]&.split(",")&.map(&:strip).compact.presence

          subfield_set = datafields(tag,
            ind1: ind1,
            ind2: ind2
          ).subfields(subfield_codes,
            flatten: flatten_subfields
          )

          flatten_subfields ? subfield_set.values(as_hash: values_as_hash) : subfield_set.map{|set| set.values(as_hash: values_as_hash)}
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

    # Record was called Document in the past. We inherit from Record
    # to avoid a breaking change.
    class Document < Record ; end
  end
end
