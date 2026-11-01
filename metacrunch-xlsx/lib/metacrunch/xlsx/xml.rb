# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # Just enough XML for the parts of a workbook, without an XML library:
    # the elements of one name, read from a stream one at a time, their
    # attributes and their text. Names match by local name, so prefixes
    # (x:row) and the Strict namespaces work. Resolves the five predefined
    # entities and character references, nothing else. Internal.
    module Xml

      BLOCK = 65_536
      ENTITIES = {"amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'"}.freeze
      ENTITY = /&(?:(amp|lt|gt|quot|apos)|#(\d+)|#x(\h+));/
      # The rest of a start tag up to its ">", which may stand in quotes.
      TAG_END = /\G(?:[^>"']|"[^"]*"|'[^']*')*>/
      ATTRIBUTE = /([A-Za-z_][\w.-]*:)?([A-Za-z_][\w.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/
      PREFIX = /(?:[A-Za-z_][\w.-]*:)?/
      TEXT = %r{<#{PREFIX}t(?=[\s>/])[^>]*?(?:/>|>(.*?)</#{PREFIX}t\s*>)}m
      PHONETIC = %r{<#{PREFIX}rPh(?=[\s>/]).*?</#{PREFIX}rPh\s*>}m
      LINE_BREAK = /\r\n?/
      # Excel's code for a character, e.g. _x000D_ for a carriage return.
      CHARACTER_CODES = /(?:_x\h{4}_)+/
      ENCODING = /\A\s*<\?xml[^>]*?encoding\s*=\s*["']([^"']+)/
      DOCTYPE = /\A\s*(?:<\?.*?\?>\s*|<!--.*?-->\s*)*<!DOCTYPE/m

      module_function

      # Yields every element named local_name in source (anything with
      # readpartial) as a UTF-8 String, from its start tag to its end tag.
      # Elements of that name must not nest. part and name label errors.
      def each_element(source, local_name, part:, name:, block: BLOCK, &)
        Elements.new(source, local_name, part, name, block).each(&)
      end

      # The attributes of an element's start tag, by local name; namespace
      # declarations are left out.
      def attributes(element) = pairs(element.match(TAG_END, 0)&.to_s || element)

      # The attributes written in text (the inside of a start tag), by
      # local name; namespace declarations are left out.
      def pairs(text)
        result = {}
        text.scan(ATTRIBUTE) do |prefix, key, double, single|
          next if prefix == "xmlns:" || (prefix.nil? && key == "xmlns")

          result[key] = unescape(double || single)
        end
        result
      end

      # The text of the t elements in fragment (a shared string, an inline
      # string), without phonetic runs, decoded.
      def text(fragment)
        raw = fragment.dup.force_encoding(Encoding::UTF_8).gsub(PHONETIC, "")
        content(raw.scan(TEXT).join)
      end

      # The text of an element's content as XML reads it: line breaks as
      # "\n" (a carriage return that is meant comes as &#13; or _x000D_),
      # references and Excel's character codes decoded.
      def content(raw) = decode(unescape(raw.gsub(LINE_BREAK, "\n")))

      # The five entities and character references; anything else stays.
      def unescape(text)
        return text unless text.include?("&")

        text.gsub(ENTITY) do |match|
          next ENTITIES.fetch(Regexp.last_match(1)) if Regexp.last_match(1)

          code = Regexp.last_match(2) ? Regexp.last_match(2).to_i : Regexp.last_match(3).hex
          character(code) || match
        end
      end

      def character(code)
        return if code > 0x10FFFF || code.between?(0xD800, 0xDFFF)

        [code].pack("U")
      end

      # Excel's character codes, a run of them as UTF-16, so a surrogate
      # pair is one character; "_x005F_" is the "_" of a literal "_x".
      def decode(text)
        return text unless text.include?("_x")

        text.gsub(CHARACTER_CODES) do |run|
          units = run.scan(/\h{4}/).map(&:hex)
          units.pack("n*").force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8, invalid: :replace)
        end
      end

      # The elements of one name in a stream, read in blocks; only the
      # unread rest and an unfinished element are kept.
      class Elements

        # Bytes read before the XML declaration and DOCTYPE are checked.
        PROLOG = 1024
        BOM = "\xEF\xBB\xBF".b
        UTF16 = ["\xFF\xFE", "\xFE\xFF", "<\0", "\0<"].map(&:b).freeze
        TAG_LIMIT = 65_536
        # Room for an end tag that a block cuts in two.
        CLOSE_LIMIT = 256

        def initialize(source, local_name, part, name, block)
          @source = source
          @local_name = local_name
          @part = part
          @name = name
          @block = block
          @start = %r{<(#{PREFIX})#{Regexp.escape(local_name)}(?=[\s>/])}
          @ends = {}
          @buffer = "".b
          @eof = false
          @searched = 0
        end

        def each
          nil while @buffer.bytesize < PROLOG && fill
          check_prolog
          position = 0
          loop do
            start = @buffer.index(@start, position)
            unless start
              position = keep(@buffer.rindex("<", -1)&.then { [it, position].max } || @buffer.bytesize)
              break unless fill

              next
            end
            stop = element_end(start, Regexp.last_match(1))
            unless stop
              position = keep(start)
              raise broken("unclosed element #{@local_name}") unless fill

              next
            end
            @searched = 0
            yield utf8(@buffer.byteslice(start, stop - start))
            position = stop
          end
        end

        private

        # The offset after the element starting at start, or nil when the
        # buffer does not hold all of it yet.
        # The search for the end tag goes on where the last one stopped
        # (@searched, from start), so a huge element is searched once. A
        # start tag longer than TAG_LIMIT is broken: rows and cells have few
        # attributes.
        def element_end(start, prefix)
          tag = @buffer.match(TAG_END, start)
          unless tag
            raise broken("unclosed element #{@local_name}") if @buffer.bytesize - start > TAG_LIMIT

            return
          end
          return tag.end(0) if @buffer.getbyte(tag.end(0) - 2) == 47 # "/>"

          close = @ends[prefix] ||= %r{</#{Regexp.escape(prefix)}#{Regexp.escape(@local_name)}\s*>}
          found = @buffer.index(close, [tag.end(0), start + @searched].max)
          return @buffer.match(close, found).end(0) if found

          @searched = [@buffer.bytesize - start - CLOSE_LIMIT, 0].max
          nil
        end

        # Drops the bytes before offset; returns 0, the new position.
        def keep(offset)
          @buffer = @buffer.byteslice(offset..)
          0
        end

        # Appends a block; false at the end of the source.
        def fill
          return false if @eof

          @buffer << @source.readpartial(@block)
          true
        rescue EOFError
          @eof = true
          false
        end

        # A UTF-16 part starts with its byte order mark or with "<" and a
        # NUL; a UTF-8 byte order mark is passed over.
        def check_prolog
          raise broken("encoding UTF-16") if UTF16.include?(@buffer.byteslice(0, 2))

          prolog = @buffer.start_with?(BOM) ? @buffer.byteslice(BOM.bytesize..) : @buffer
          encoding = prolog.match(ENCODING)&.[](1)
          raise broken("encoding #{encoding}") if encoding && !encoding.casecmp?("UTF-8")
          raise broken("has a DOCTYPE") if prolog.match?(DOCTYPE)
        end

        def utf8(bytes)
          text = bytes.force_encoding(Encoding::UTF_8)
          raise broken("not valid UTF-8") unless text.valid_encoding?

          text
        end

        def broken(reason) = Xlsx.broken(@name, @part, reason)

      end

    end
  end
end
