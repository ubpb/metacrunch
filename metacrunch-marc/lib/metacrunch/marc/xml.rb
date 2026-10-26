# frozen_string_literal: true

module Metacrunch
  module Marc
    # MARCXML, MARC 21 in XML: parsed with Ox (Xml::Parser), cut into record
    # strings without parsing (Xml::Splitter) and written by Record#to_xml
    # (Xml::Serializer).
    module Xml

      # The namespace of the MARC 21 XML schema.
      NAMESPACE = "http://www.loc.gov/MARC21/slim"

      # The start and the end of a collection, as the Writer writes them.
      HEADER = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<collection xmlns=\"#{NAMESPACE}\">\n".freeze
      FOOTER = "</collection>\n"

      class << self

        # The one record in xml, a String with one <record>, bare or in a
        # <collection>. Raises ParseError for none or more than one.
        def parse(xml, normalize: nil)
          raise ArgumentError, "xml must be a String, got #{xml.class}" unless xml.is_a?(String)

          records = each(xml, normalize:).to_a
          raise ParseError, "no record found" if records.empty?
          if records.size > 1
            raise ParseError, "#{records.size} records found where one was expected (use Marc::Xml.each)"
          end

          records.first
        end

        # Yields every record of input: a String, or an object with
        # readpartial or read (a File, a Zlib::GzipReader, a pipe). Without a
        # block an Enumerator.
        def each(input, normalize: nil, &block)
          Marc.check_input(input)
          Marc.check_normalize(normalize)
          return enum_for(:each, input, normalize:) unless block

          Parser.run(source(input), normalize:, &block)
          nil
        end

        # Yields every record of input as a String from its start tag to its
        # end tag, without parsing it. Without a block an Enumerator.
        def each_raw(input, &block)
          Marc.check_input(input)
          return enum_for(:each_raw, input) unless block

          Splitter.new(input).each(&block)
          nil
        end

        private

        # Ox is superlinear on a String; it reaches Ox through readpartial, as
        # all input does (see UntilNul).
        def source(input) = input.is_a?(String) ? StringSource.new(input) : input

      end

    end
  end
end
