# frozen_string_literal: true

module Metacrunch
  module Redis
    # The checks of the components' options; they raise ArgumentError.
    module Options

      module_function

      def string(value, name)
        return value if value.is_a?(String) && !value.empty?

        raise ArgumentError, "#{name} must be a non-empty String, got #{value.inspect}"
      end

      def positive_integer(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
      end

      def seconds(value, name)
        return value if value.is_a?(Numeric) && value.positive?

        raise ArgumentError, "#{name} must be a positive number of seconds, got #{value.inspect}"
      end

    end
  end
end
