# frozen_string_literal: true

module Metacrunch
  module Marc
    # Wraps an object with readpartial or read so that Marc.each can look at
    # its first bytes before a format module reads it: peek keeps the bytes
    # it reads, and readpartial hands them out before reading on. Internal.
    class Lookahead

      def initialize(io)
        @io = io
        @buffer = String.new(encoding: Encoding::BINARY)
        @eof = false
      end

      # Up to length bytes ahead, without consuming them; fewer at the end.
      def peek(length)
        while @buffer.bytesize < length && (chunk = read(length - @buffer.bytesize))
          @buffer << chunk.b
        end
        @buffer.byteslice(0, length)
      end

      # The bytes peek kept, then the input's; EOFError at the end, as
      # IO#readpartial.
      def readpartial(length)
        return @buffer.slice!(0, length) unless @buffer.empty?

        read(length) or raise EOFError, "end of input reached"
      end

      private

      # A chunk of at most length bytes; nil at the end.
      def read(length)
        return if @eof

        chunk = @io.respond_to?(:readpartial) ? @io.readpartial(length) : @io.read(length)
        @eof = chunk.nil? || chunk.empty?
        chunk unless @eof
      rescue EOFError
        @eof = true
        nil
      end

    end
  end
end
