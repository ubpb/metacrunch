# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # Cuts MARCXML into record strings without parsing it (Marcxml.each_xml).
    # The record element name, with its prefix, is taken from the first
    # record start tag; a record runs from a start tag to the next matching
    # end tag. An end tag inside CDATA or a comment cuts a record there; a
    # record cut off by the end of the input is yielded as it is. Internal.
    class Splitter

      CHUNK_SIZE = 65_536

      # Bytes kept while no start tag is found, for a tag cut by a chunk
      # boundary.
      KEEP = 256

      FIRST_START = %r{<(?:([A-Za-z_][\w.-]*):)?record[\s>/]}n

      SLASH = "/".ord

      def initialize(input)
        @input = input.is_a?(String) ? StringSource.new(input) : input
        @buffer = String.new(encoding: Encoding::BINARY)
        @position = 0
        @start = nil
        @end_tag = nil
      end

      def each
        loop do
          if (xml = take)
            yield xml
          elsif !read_more?
            break
          end
        end
        rest = remainder
        yield rest if rest
      end

      private

      # The next whole record in the buffer, or nil.
      def take
        return unless detected?

        first = @buffer.index(@start, @position)
        return skip unless first

        @position = first
        open_end = @buffer.index(">", first)
        return unless open_end
        return slice(first, open_end + 1) if @buffer.getbyte(open_end - 1) == SLASH

        close = @buffer.index(@end_tag, open_end)
        close && slice(first, close + @end_tag.bytesize)
      end

      # Finds the record element name in the first start tag; false until
      # it is in the buffer.
      def detected?
        return true if @start

        match = FIRST_START.match(@buffer, @position)
        unless match
          skip
          return false
        end

        prefix = match[1] ? "#{match[1]}:" : ""
        @start = %r{<#{Regexp.escape(prefix)}record[\s>/]}n
        @end_tag = "</#{prefix}record>".b
        true
      end

      # The rest of the input from a record start tag on, at its end: a
      # record the input cut off, which fails when it is parsed. nil if
      # there is none.
      def remainder
        return unless @start

        first = @buffer.index(@start, @position)
        first && slice(first, @buffer.bytesize)
      end

      # Drops the buffer but its last bytes. Returns nil.
      def skip
        @position = [@position, @buffer.bytesize - KEEP].max
        nil
      end

      def slice(from, to)
        @position = to
        @buffer.byteslice(from, to - from).force_encoding(Encoding::UTF_8)
      end

      # Appends the next chunk, dropping what was taken; false at the end of
      # the input.
      def read_more?
        chunk = read
        return false unless chunk

        @buffer = @buffer.byteslice(@position..) << chunk.b
        @position = 0
        true
      end

      def read
        chunk = @input.respond_to?(:readpartial) ? @input.readpartial(CHUNK_SIZE) : @input.read(CHUNK_SIZE)
        chunk unless chunk.nil? || chunk.empty?
      rescue EOFError
        nil
      end

    end
  end
end
