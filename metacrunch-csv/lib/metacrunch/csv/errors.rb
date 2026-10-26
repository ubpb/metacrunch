# frozen_string_literal: true

module Metacrunch
  module Csv
    # A row that has more fields than there are columns; the error of its
    # InvalidRecord.
    class ParseError < Metacrunch::Error; end
  end
end
