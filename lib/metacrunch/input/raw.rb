# frozen_string_literal: true

module Metacrunch
  class Input
    # The bytes of a file or an IO, as the source of a Stream. Counts them
    # for progress if count is given. Internal.
    class Raw

      # io: responds to readpartial or read. count: called with the size of
      # every block, or nil.
      def initialize(io, name, count: nil)
        @io = io
        @name = name
        @count = count
        @partial = io.respond_to?(:readpartial)
      end

      def readpartial(length)
        block = @partial ? @io.readpartial(length) : read(length)
        @count&.call(block.bytesize)
        block
      rescue SystemCallError => e
        raise InputError, "#{@name}: #{Files.reason(e)}"
      end

      private

      def read(length)
        block = @io.read(length)
        raise EOFError, "end of file reached" if block.nil? || block.empty?

        block
      end

    end
  end
end
