# frozen_string_literal: true

module Metacrunch
  module Ai
    # An extractor for plain text and Markdown: the content as it is, as
    # UTF-8 (bytes taken as UTF-8, or as UTF-16 after its byte order mark,
    # invalid ones replaced; a String of another encoding converted),
    # without a byte order mark and with LF line ends.
    #
    # YAML front matter at the start, between a line "---" and a line "---"
    # or "...", gives the title, the language and further fields (dates as
    # ISO 8601 Strings), and is removed from the text. Front matter that
    # cannot be read stays in the text, with the mark "Front matter not
    # read"; a start that is no YAML mapping (a rule) is text.
    #
    # Pages: a line that holds only the page_break marker, or a form feed,
    # ends a page; the text is then an Array of pages, as Tika gives a PDF's.
    # The default marker is the one Docling writes with
    # export_to_markdown(page_break_placeholder="<!-- page break -->").
    class Text

      TYPES = ["text/plain", "text/markdown"].freeze
      UTF16 = {"\xFF\xFE".b => Encoding::UTF_16LE, "\xFE\xFF".b => Encoding::UTF_16BE}.freeze
      FRONT_MATTER = /\A---[ \t]*\n(.*?)^(?:---|\.\.\.)[ \t]*(?:\n|\z)/m
      UNREAD = "Front matter not read"
      PAGE_BREAK = "<!-- page break -->"

      # page_break: the marker line, or nil for form feeds only.
      def initialize(page_break: PAGE_BREAK)
        unless page_break.nil? || (page_break.is_a?(String) && !page_break.strip.empty?)
          raise ArgumentError, "page_break must be a marker or nil, got #{page_break.inspect}"
        end

        marker = /^[ \t]*#{Regexp.escape(page_break.strip)}[ \t]*(?:\n|\z)/ if page_break
        @pages = Regexp.union(*["\f", marker].compact)
      end

      def types = TYPES

      # Takes type: as every extractor does; the text is the same for both.
      def extract(content, **)
        text = utf8(content.to_s).scrub.delete_prefix("﻿").gsub("\r\n", "\n")
        fields, text, mark = front_matter(text)
        text = text.split(@pages, -1) if text.match?(@pages)
        {text:, title: present(fields.delete("title")), lang: present(fields.delete("lang")), fields:, mark:}
      end

      private

      def utf8(text)
        if text.encoding == Encoding::BINARY
          bom, encoding = UTF16.find { |prefix, _| text.start_with?(prefix) }
          return text.dup.force_encoding(Encoding::UTF_8) unless encoding

          text = text.byteslice(bom.bytesize..).force_encoding(encoding)
        end
        text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      # [fields, the text without front matter, a mark or nil].
      def front_matter(text)
        match = FRONT_MATTER.match(text)
        return [{}, text, nil] unless match

        data = YAML.safe_load(match[1], permitted_classes: [Date, Time]) || {}
        data.is_a?(Hash) ? [json(data), match.post_match, nil] : [{}, text, nil]
      rescue Psych::Exception
        [{}, text, UNREAD]
      end

      # Keys as Strings, dates and times as ISO 8601 Strings.
      def json(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, json(item)] }
        when Array then value.map { json(it) }
        when Date, Time then value.iso8601
        else value
        end
      end

      def present(value)
        text = value.to_s.strip
        text unless text.empty?
      end

    end
  end
end
