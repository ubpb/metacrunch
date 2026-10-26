# frozen_string_literal: true

module Metacrunch
  module Marc
    # Checks subfield code arguments: Strings, also in Arrays. Internal.
    module Codes

      module_function

      # codes as a flat Array of Strings; ArgumentError for other codes. The
      # usual case, Strings only, allocates nothing.
      def check(codes)
        return codes if codes.all?(String)

        codes = codes.flatten
        return codes if codes.all?(String)

        raise ArgumentError, "a code must be a String, got #{codes.find { !it.is_a?(String) }.inspect}"
      end

    end
  end
end
