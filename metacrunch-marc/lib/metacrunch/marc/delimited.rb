# frozen_string_literal: true

module Metacrunch
  module Marc
    # Cuts input (a String, or an object with readpartial or read) into
    # binary pieces that end with a delimiter byte; the rest after the last
    # delimiter, if any, comes last. Searches go on where they stopped and
    # taken pieces are dropped once they exceed a chunk, so the time grows in
    # proportion to the input, however long a piece is. Internal.
    class Delimited

      CHUNK_SIZE = 65_536

      def initialize(input, delimiter)
        # A String is the buffer itself, with nothing more to read.
        @input = input.is_a?(String) ? nil : input
        @delimiter = delimiter
        @buffer = input.is_a?(String) ? input.b : String.new(encoding: Encoding::BINARY)
        # Where the next piece starts.
        @position = 0
        # Where the search for the delimiter goes on.
        @scan = 0
      end

      def each
        loop do
          if (piece = take)
            yield piece
          elsif !read_more?
            break
          end
        end
        yield slice(@buffer.bytesize) if @position < @buffer.bytesize
      end

      private

      # The next whole piece in the buffer, or nil.
      def take
        found = @buffer.byteindex(@delimiter, @scan)
        unless found
          @scan = @buffer.bytesize
          return
        end

        @scan = found + 1
        slice(found + 1)
      end

      def slice(to)
        piece = @buffer.byteslice(@position, to - @position)
        @position = to
        piece
      end

      # Appends the next chunk; false at the end of the input.
      def read_more?
        chunk = read
        return false unless chunk

        compact if @position > CHUNK_SIZE
        @buffer << (chunk.encoding == Encoding::BINARY ? chunk : chunk.b)
        true
      end

      def compact
        @buffer = @buffer.byteslice(@position, @buffer.bytesize - @position)
        @scan -= @position
        @position = 0
      end

      def read
        return unless @input

        chunk = @input.respond_to?(:readpartial) ? @input.readpartial(CHUNK_SIZE) : @input.read(CHUNK_SIZE)
        chunk unless chunk.nil? || chunk.empty?
      rescue EOFError
        nil
      end

    end
  end
end
