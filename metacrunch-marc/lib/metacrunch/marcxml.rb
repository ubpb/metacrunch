require "active_support"
require "active_support/core_ext"
require "ox"

module Metacrunch
  require_relative "marcxml/version"
  require_relative "marcxml/parser"
  require_relative "marcxml/document"

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
      # Parses a MARCXML string into a {Metacrunch::Marcxml::Document}.
      #
      # @param xml [String] the MARCXML document as a string
      # @param collection_mode [true, false] set to `true` if the MARCXML contains more than one record.
      #  Default is `false`.
      # @return [Metacrunch::Marcxml::Document, Array<Metacrunch::Marcxml::Document>, nil] the parsed
      #   {Metacrunch::Marcxml::Document}, an array of documents if `collection_mode` was `true`
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
      def [](xml)
        self.parse(xml, collection_mode: false)
      end
    end
  end

end
