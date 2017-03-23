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
    # Convenience method for Metacrunch::Marcxml.parse
    #
    # @return [Metacrunch::Marcxml::Document] the parsed {Metacrunch::Marcxml::Document}
    # @see Metacrunch::Marcxml#parse
    #
    def Marcxml(xml)
      Metacrunch::Marcxml.parse(xml)
    end
  end


  module Marcxml
    class << self
      #
      # Parses a MARCXML string into a {Metacrunch::Marcxml::Document}.
      #
      # @param xml [String] the MARCXML document as a string
      # @return [Metacrunch::Marcxml::Document] the parsed {Metacrunch::Marcxml::Document}
      #
      def parse(xml)
        Parser.new.parse(xml)
      end
    end
  end

end
