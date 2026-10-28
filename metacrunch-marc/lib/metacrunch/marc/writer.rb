# frozen_string_literal: true

require "metacrunch"

module Metacrunch
  module Marc
    # A metacrunch sink: writes records as MARCXML, ISO 2709 or MARC-in-JSON
    # to what Metacrunch::Output takes: a file (.gz compressed), stdout ("-")
    # or an IO. MARCXML is one <collection>, whose end close writes also
    # after an aborted run, so the output stays well-formed; ISO 2709 records
    # follow each other; MARC-in-JSON has one record per line.
    class Writer

      FORMATS = [:xml, :iso2709, :json].freeze
      OVERSIZE = [nil, :error, :allow].freeze
      NAMES = {xml: "MARCXML", iso2709: "ISO 2709", json: "MARC-in-JSON"}.freeze

      # Strings written as they are, e.g. serialized in a worker: a record
      # element (any prefix), an ISO 2709 record, one line of MARC-in-JSON.
      # Matched as binary, since a regexp raises on invalid UTF-8.
      XML_RECORD = %r{\A\s*<(?:[A-Za-z_][\w.-]*:)?record[\s>/]}n
      ISO2709_RECORD = /\A\d{5}/n
      JSON_RECORD = /\A\s*\{[^\n]*\n?\z/n

      # format: :xml, :iso2709 or :json. oversize: (ISO 2709 only) :error,
      # the default, or :allow; see Record#to_iso2709.
      def initialize(target, format:, oversize: nil)
        unless FORMATS.include?(format)
          raise ArgumentError, "format must be :xml, :iso2709 or :json, got #{format.inspect}"
        end
        unless OVERSIZE.include?(oversize)
          raise ArgumentError, "oversize must be :error or :allow, got #{oversize.inspect}"
        end
        raise ArgumentError, "oversize: is for format: :iso2709 only" if oversize && format != :iso2709

        @output = Metacrunch::Output.new(target)
        @format = format
        @oversize = oversize || :error
        @open = false
      end

      def open(_context)
        @output.open
        @open = true
        @output.write(Xml::HEADER) if @format == :xml
      end

      def write(record, ctx)
        @output.write(serialize(record, ctx))
      end

      # Joins the batch as bytes, so Strings in other encodings (binary ISO
      # 2709 records) can be mixed with UTF-8 ones.
      def write_batch(records, ctxs)
        batch = String.new(encoding: Encoding::BINARY)
        records.zip(ctxs) { |record, ctx| batch << serialize(record, ctx).b }
        @output.write(batch)
      end

      # Writes the records so far to the file or stream (a FLUSH of the
      # source); a MARCXML collection lacks its end until close.
      def flush = @output.flush

      # Writes the end of a MARCXML collection, also after an aborted run,
      # and closes the output. Does nothing the second time.
      def close
        return unless @open

        @open = false
        @output.write(Xml::FOOTER) if @format == :xml
      ensure
        @output.close
      end

      private

      # A Record is serialized here; a String of the format (serialized in a
      # worker, cheaper to send) is written as it is.
      def serialize(record, ctx)
        case record
        when Record then serialize_record(record)
        when String then string(record, ctx)
        else
          raise Metacrunch::Error,
                "record at position #{ctx.position} is not a Metacrunch::Marc::Record (#{record.class})"
        end
      rescue SerializeError => e
        raise Metacrunch::Error,
              "record at position #{ctx.position} cannot be written as #{NAMES[@format]}: #{e.message}"
      end

      def serialize_record(record)
        case @format
        when :xml then Xml::Serializer.record(record, namespace: false, indent: "  ")
        when :iso2709 then Iso2709::Serializer.record(record, oversize: @oversize)
        else "#{Json::Serializer.record(record)}\n"
        end
      end

      def string(string, ctx)
        bytes = string.b
        case @format
        when :xml
          bytes.match?(XML_RECORD) ? line(string) : refuse(ctx, "a <record> element")
        when :iso2709
          iso2709 = bytes.match?(ISO2709_RECORD) && bytes.end_with?(Iso2709::RECORD_TERMINATOR)
          iso2709 ? string : refuse(ctx, "an ISO 2709 record")
        else
          bytes.match?(JSON_RECORD) ? line(string) : refuse(ctx, "one line of MARC-in-JSON")
        end
      end

      def line(string) = string.end_with?("\n") ? string : "#{string}\n"

      def refuse(ctx, kind)
        raise Metacrunch::Error, "record at position #{ctx.position} is a String but not #{kind}"
      end

    end
  end
end
