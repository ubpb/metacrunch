# frozen_string_literal: true

module Metacrunch
  module Ai
    # An extractor for plain text and Markdown: the content as it is, as
    # UTF-8 (bytes taken as UTF-8, invalid ones replaced; a String of
    # another encoding converted), without a byte order mark and with LF
    # line ends.
    class Text

      TYPES = ["text/plain", "text/markdown"].freeze

      def types = TYPES

      # Takes type: as every extractor does; the text is the same for both.
      def extract(content, **)
        {text: utf8(content.to_s).scrub.delete_prefix("﻿").gsub("\r\n", "\n"), title: nil, lang: nil}
      end

      private

      def utf8(text)
        return text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY

        text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

    end
  end
end
