# frozen_string_literal: true

require "metacrunch"

module Metacrunch
  module Marc
    # A metacrunch source: reads MARCXML from what Metacrunch::Input reads
    # (paths, "-" for stdin, IOs or an Array of them; gzip and tar are
    # unpacked whatever their names) and yields a Record per record, or
    # with parse: false its XML string, which is cheaper to send to workers.
    # A record that cannot be parsed is yielded as Metacrunch::InvalidRecord;
    # a document that does not start like XML raises Metacrunch::InputError.
    class Reader

      BOM = "\xEF\xBB\xBF".b

      # targets: what Metacrunch::Input takes. IOs are never closed.
      def initialize(targets, parse: true, normalize: nil)
        @input = Metacrunch::Input.new(targets)
        Marc.check_normalize(normalize)
        if normalize && !parse
          raise ArgumentError, "normalize: needs parse: true; with parse: false normalize in the step that parses: " \
                               "Metacrunch::Marc::Xml.parse(xml, normalize: :nfc)"
        end
        @parse = parse
        @normalize = normalize
      end

      # Without a block an Enumerator.
      def each
        return enum_for(:each) unless block_given?

        @input.each_document do |stream, name|
          check_xml(stream, name)
          Xml.each_raw(stream) { |xml| yield(@parse ? record(xml) : xml) }
        end
      end

      # The share of the input read so far; see Metacrunch::Input#progress.
      def progress = @input.progress

      private

      # After a byte order mark and whitespace, a document must start with
      # "<"; an empty one passes.
      def check_xml(stream, name)
        text = stream.peek(64).delete_prefix(BOM).lstrip
        return if text.empty? || text.start_with?("<")

        raise Metacrunch::InputError, "#{name}: is not XML: it starts with #{text[0, 16].inspect}"
      end

      def record(xml)
        Xml.parse(xml, normalize: @normalize)
      rescue ParseError => e
        Metacrunch::InvalidRecord.new(raw: xml, error: e)
      end

    end
  end
end
