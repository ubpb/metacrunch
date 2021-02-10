require "active_support"
require "active_support/core_ext"
require "ox"

module Metacrunch
  require_relative "marcxml/version"
  require_relative "marcxml/parser"
  require_relative "marcxml/record"

  class << self
    #
    # Convenience method for Metacrunch::Marcxml.parse
    #
    # @see Metacrunch::Marcxml#parse
    #
    def Marcxml(xml, collection_mode: false)
      Metacrunch::Marcxml.parse(xml, collection_mode: collection_mode)
    end
  end


  module Marcxml
    class << self
      #
      # Parses a MARCXML string into a {Metacrunch::Marcxml::Record}.
      #
      # @param xml [String] the MARCXML as a string
      # @param collection_mode [true, false] set to `true` if the MARCXML contains a collection
      #   of records. Default is `false`.
      # @return [Metacrunch::Marcxml::Record, Array<Metacrunch::Marcxml::Record>, nil] the parsed
      #   {Metacrunch::Marcxml::Record}, an array of records if `collection_mode` was `true`
      #   or `nil` if the MARCXML did not contain valid data.
      #
      def parse(xml, collection_mode: false)
        Parser.new.parse(xml, collection_mode: collection_mode)
      end

      #
      # Convenience method for Metacrunch::Marcxml.parse(xml, collection_mode: false)
      #
      # @see Metacrunch::Marcxml#parse
      #
      def [](xml, collection_mode: false)
        self.parse(xml, collection_mode: collection_mode)
      end
    end
  end

end
