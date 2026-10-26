# frozen_string_literal: true

module Metacrunch
  module Csv
    # The bytes of a Metacrunch::Input::Stream as Ruby's CSV reads its
    # input: gets and eof?. Blocks are tagged with the encoding and, as with
    # IO#gets, never end inside a character. Internal.
    class Lines

      BLOCK = 65_536

      def initialize(stream, encoding)
        @stream = stream
        @encoding = encoding
        @binary = encoding == Encoding::BINARY
      end

      # The next block of up to limit bytes. CSV's separator does not
      # matter: it splits rows itself.
      def gets(_separator = nil, limit = BLOCK)
        data = @stream.read(limit)
        return if data.nil?

        data.force_encoding(@encoding)
        @binary || data.valid_encoding? ? data : complete(data)
      end

      def eof? = @stream.eof?

      def external_encoding = @encoding

      def internal_encoding = nil

      private

      # Adds up to three bytes, as many as a character split at the end of
      # the block needs. Invalid bytes elsewhere stay invalid.
      def complete(data)
        bytes = data.b
        3.times do
          break if @stream.eof?

          bytes << @stream.read(1)
          break if bytes.dup.force_encoding(@encoding).valid_encoding?
        end
        bytes.force_encoding(@encoding)
      end

    end
  end
end
