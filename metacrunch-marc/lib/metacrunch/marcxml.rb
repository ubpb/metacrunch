require "rubygems"
require "active_support"
require "active_support/core_ext"
require "htmlentities"
require "ox"

require_relative "./marcxml/version"
require_relative "./marcxml/parser"
require_relative "./marcxml/document"

module Metacrunch
  class << self
    #
    # Parse MARCXML. Convenience method for Metacrunch::Marcxml.parse
    #
    def Marcxml(xml)
      Metacrunch::Marcxml.parse(xml)
    end
  end


  module Marcxml
    class << self
      #
      # Parses a MARCXML string into a Metacrunch::Marcxml::Document.
      #
      # @param [String] XML string of a MARCXML document
      # @return [Metacrunch::Marcxml::Document]
      #
      def parse(xml)
        Parser.new.parse(xml)
      end
    end
  end
end
