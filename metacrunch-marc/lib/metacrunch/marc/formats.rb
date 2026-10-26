# frozen_string_literal: true

module Metacrunch
  module Marc
    # Tells the format of a document from its first bytes, after a UTF-8 byte
    # order mark and after space, tab, line breaks and NUL: "<" is MARCXML,
    # "{" MARC-in-JSON, five digits at 0-4 and at 12-16 (record length and
    # base address) ISO 2709, "[" a JSON array. The base address keeps a CSV
    # file that starts with a number from being taken for ISO 2709. Internal.
    module Formats

      # Detection looks at the first WINDOW bytes of a String, and at twice
      # as many while it cannot tell.
      WINDOW = 64
      ISO2709 = /\A\d{5}.{7}\d{5}/mn
      ISO2709_START = 17
      EXCERPT = 16

      # The message for a document of format :array.
      ARRAY = "a JSON array of records; convert it to one record per line first, e.g. " \
              "jq -c '.[]' in.json > out.jsonl"

      module_function

      # The format of a document and the bytes seen, [format, head]: format
      # is :xml, :iso2709, :json, :array, :none (nothing but skipped bytes)
      # or :unknown. The block gives the first length bytes of the document,
      # fewer at its end; window is the first length asked for.
      def detect(window = WINDOW)
        loop do
          head = yield(window).b
          format = format(head, complete: head.bytesize < window)
          return [format, head] if format

          window *= 2
        end
      end

      # The format of head; nil if more bytes follow (complete: false) and
      # head does not tell yet.
      def format(head, complete:)
        return if !complete && head.bytesize < BOM.bytesize && BOM.start_with?(head)

        start = start(head)
        return complete ? :none : nil unless start

        case head.getbyte(start)
        when 0x3C then :xml
        when 0x7B then :json
        when 0x5B then :array
        when 0x30..0x39 then iso2709(head, start, complete)
        else :unknown
        end
      end

      # The module that reads format; Json also for :array, whose parse
      # explains why it cannot.
      def library(format)
        case format
        when :xml then Xml
        when :iso2709 then Iso2709
        else Json
        end
      end

      # Whether string, one record, is ISO 2709 by its ends: content that
      # starts with a digit and ends with the record terminator. A document
      # needs the record length and the base address; one record, as
      # Iso2709.parse reads it, does not.
      def iso2709_record?(string)
        bytes = string.b
        first = start(bytes)
        return false unless first && bytes.getbyte(first).between?(0x30, 0x39)

        bytes.getbyte(bytes.rindex(CONTENT)) == Iso2709::RECORD_TERMINATOR.ord
      end

      # The message for a document of format :unknown.
      def unknown(head)
        excerpt = head.byteslice(start(head) || 0, EXCERPT)
        "neither MARCXML, ISO 2709 nor MARC-in-JSON: it starts with #{excerpt.inspect}"
      end

      def iso2709(head, start, complete)
        return :iso2709 if head.byteslice(start, ISO2709_START).match?(ISO2709)
        return if !complete && head.bytesize - start < ISO2709_START

        :unknown
      end

      # Where the content starts, after a byte order mark and skipped bytes.
      def start(head) = head.index(CONTENT, head.start_with?(BOM) ? BOM.bytesize : 0)

    end
  end
end
