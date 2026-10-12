# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Selects fields by tag matchers and indicator filters (see Record).
    # The class methods check indicators without an instance, for the
    # indexed queries of Record. Internal.
    class Filter

      # filter itself if it is an indicator filter: nil, a String or an Array
      # of Strings. Raises ArgumentError otherwise.
      def self.indicator(filter, name)
        return filter if filter.nil? || filter.is_a?(String)
        return filter if filter.is_a?(Array) && filter.all?(String)

        raise ArgumentError, "#{name} must be nil, a String or an Array of Strings, got #{filter.inspect}"
      end

      # Whether field passes the indicator filters; control fields pass only
      # without filters.
      def self.indicators?(field, ind1, ind2)
        return true if ind1.nil? && ind2.nil?
        return false unless field.is_a?(DataField)

        indicator?(ind1, field.ind1) && indicator?(ind2, field.ind2)
      end

      def self.indicator?(filter, value)
        return true if filter.nil?

        filter.is_a?(String) ? filter == value : filter.include?(value)
      end

      def initialize(tags, ind1, ind2)
        @any_tag = tags.empty?
        @strings = []
        @patterns = []
        tags.each { add(it) }
        @ind1 = Filter.indicator(ind1, "ind1")
        @ind2 = Filter.indicator(ind2, "ind2")
      end

      def matches?(field) = tag?(field.tag) && Filter.indicators?(field, @ind1, @ind2)

      private

      def add(tag)
        case tag
        when String then @strings << tag
        when Array then tag.each { add(it) }
        when Range then @strings.concat(range(tag))
        when Regexp then @patterns << tag
        else raise ArgumentError, "a tag must be a String, an Array, a Range or a Regexp, got #{tag.inspect}"
        end
      end

      def range(range)
        return range.to_a if range.begin.is_a?(String) && range.end.is_a?(String)

        raise ArgumentError, "a tag range must have String ends, got #{range.inspect}"
      end

      def tag?(tag)
        @any_tag || @strings.include?(tag) || (!tag.nil? && @patterns.any? { it.match?(tag) })
      end

    end
  end
end
