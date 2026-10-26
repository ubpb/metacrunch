# frozen_string_literal: true

module Metacrunch
  class Input
    # The bytes of one document: a file, the content of a gzip layer, a tar
    # member or an IO. Reads its source in blocks of BLOCK bytes through the
    # source's readpartial; all Strings it returns are binary and new. Valid
    # until the next document is yielded or the iteration ends.
    class Stream

      BLOCK = 65_536
      NEWLINE = "\n".b

      # source: an object whose readpartial(length) returns up to length
      # bytes and raises EOFError at the end.
      def initialize(source)
        @source = source
        @buffer = "".b
        @eof = false
        @closed = false
      end

      # Up to length bytes, nil at the end; without length the rest ("" at
      # the end).
      def read(length = nil)
        check_open
        return take(fill_all) if length.nil?
        return "".b if length.zero?

        fill(length)
        @buffer.empty? ? nil : take([length, @buffer.bytesize].min)
      end

      # 1 to length bytes; raises EOFError at the end. With outbuf, its
      # content is replaced and outbuf returned.
      def readpartial(length, outbuf = nil)
        check_open
        fill(1)
        raise EOFError, "end of document reached" if @buffer.empty?

        data = take([length, @buffer.bytesize].min)
        outbuf ? outbuf.replace(data) : data
      end

      # Yields every line with its "\n"; the last one may lack it. Without
      # a block an Enumerator. Bytes searched once for "\n" are not searched
      # again, so a long line costs time in proportion to its length.
      def each_line(&)
        return enum_for(:each_line) unless block_given?

        check_open
        searched = 0
        loop do
          fill(1)
          break if @buffer.empty?

          if @buffer.byteindex(NEWLINE, searched)
            take(@buffer.byterindex(NEWLINE) + 1).each_line(&)
            searched = 0
          elsif @eof
            yield take(@buffer.bytesize)
          else
            searched = @buffer.bytesize
            @buffer << next_block
          end
        end
        nil
      end

      # Up to length bytes ahead, without consuming them ("" at the end).
      def peek(length)
        check_open
        fill(length)
        @buffer.byteslice(0, length)
      end

      def eof?
        check_open
        fill(1)
        @buffer.empty?
      end

      # Internal: up to length bytes ahead, after reading one more block if
      # fewer are buffered, and whether that is all of them (length bytes,
      # or the end). Detection asks again until it can decide, so it never
      # waits for more than one block of a slow pipe.
      def lookahead(length)
        check_open
        @buffer << next_block if @buffer.bytesize < length && !@eof
        [@buffer.byteslice(0, length), @buffer.bytesize >= length || @eof]
      end

      # Internal: puts bytes back in front of the buffer (the rest that a
      # gzip member did not use).
      def unread(bytes)
        @buffer = bytes.b + @buffer
      end

      # Internal: ends the stream for its reader.
      def close
        @closed = true
      end

      private

      def check_open
        raise IOError, "stream closed" if @closed
      end

      # Reads blocks until the buffer holds length bytes or the source ends.
      def fill(length)
        @buffer << next_block while @buffer.bytesize < length && !@eof
      end

      def fill_all
        @buffer << next_block until @eof
        @buffer.bytesize
      end

      # The next block as a binary String, or "" at the end (and @eof set).
      # The sources of the layer hand out binary Strings; a String of
      # another encoding (from an IO) is copied, not changed.
      def next_block
        block = @source.readpartial(BLOCK)
        block.encoding == Encoding::BINARY ? block : block.b
      rescue EOFError
        @eof = true
        "".b
      end

      def take(length)
        data = @buffer.byteslice(0, length)
        @buffer = @buffer.byteslice(length, @buffer.bytesize - length)
        data
      end

    end
  end
end
