# frozen_string_literal: true

require "metacrunch"

module Metacrunch
  module Marcxml
    # A metacrunch sink: writes Records as one MARCXML <collection> to what
    # Metacrunch::Output takes: a file (.gz compressed), stdout ("-") or an
    # IO. close writes the end of the collection, also after an aborted run,
    # so the output stays well-formed.
    class Writer

      HEADER = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<collection xmlns=\"#{NAMESPACE}\">\n".freeze
      FOOTER = "</collection>\n"

      # A String record must start with a record element, e.g. from
      # Record#to_xml(namespace: false) in a worker.
      RECORD_START = %r{\A\s*<(?:[A-Za-z_][\w.-]*:)?record[\s>/]}

      def initialize(target)
        @output = Metacrunch::Output.new(target)
        @open = false
      end

      def open(_context)
        @output.open
        @open = true
        @output.write(HEADER)
      end

      def write(record, ctx)
        @output.write(xml(record, ctx))
      end

      def write_batch(records, ctxs)
        @output.write(records.zip(ctxs).map { |record, ctx| xml(record, ctx) }.join)
      end

      # Writes the end of the collection, also after an aborted run, and
      # closes the output. Does nothing the second time.
      def close
        return unless @open

        @open = false
        @output.write(FOOTER)
      ensure
        @output.close
      end

      private

      # A Record is serialized here; a String with a record element (record
      # XML serialized in a worker, cheaper to send) is written as it is.
      def xml(record, ctx)
        case record
        when Record then Serializer.record(record, namespace: false, indent: "  ")
        when String then record_xml(record, ctx)
        else
          raise Metacrunch::Error,
                "record at position #{ctx.position} is not a Metacrunch::Marcxml::Record (#{record.class})"
        end
      rescue SerializeError => e
        raise Metacrunch::Error, "record at position #{ctx.position} cannot be written as MARCXML: #{e.message}"
      end

      def record_xml(xml, ctx)
        unless xml.match?(RECORD_START)
          raise Metacrunch::Error, "record at position #{ctx.position} is a String but not a <record> element"
        end

        xml.end_with?("\n") ? xml : "#{xml}\n"
      end

    end
  end
end
