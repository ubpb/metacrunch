# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Hands Ox a StringIO through readpartial only. Ox reads a StringIO's
    # string directly, which is superlinear in its size, as for a String
    # (see StringSource). Internal.
    class IoSource

      def initialize(io)
        @io = io
      end

      def readpartial(length) = @io.readpartial(length)

    end
  end
end
