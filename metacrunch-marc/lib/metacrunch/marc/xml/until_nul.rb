# frozen_string_literal: true

module Metacrunch
  module Marc
    module Xml
      # Hands Ox the input (a StringSource, or an object with readpartial or
      # read) through readpartial only, up to its first NUL byte. XML does not
      # allow NUL, and Ox would take it for the end of the input without an
      # error; Parser raises instead. Through readpartial Ox also does not
      # read a StringIO's string directly, which is superlinear in its size
      # (see StringSource). Internal.
      class UntilNul

        NUL = "\x00".b

        # The offset of the first NUL byte, once it is read; nil before.
        attr_reader :nul

        def initialize(input)
          @input = input
          @offset = 0
          @nul = nil
        end

        # The input's next chunk, asking for length bytes, cut off at the NUL
        # byte; EOFError at the end and after the NUL, as IO#readpartial.
        def readpartial(length)
          chunk = read(length) unless @nul
          raise EOFError, "end of input reached" unless chunk

          if (index = chunk.byteindex(NUL))
            @nul = @offset + index
            chunk = chunk.byteslice(0, index)
          end
          @offset += chunk.bytesize
          chunk
        end

        private

        def read(length)
          chunk = @input.respond_to?(:readpartial) ? @input.readpartial(length) : @input.read(length)
          chunk unless chunk.nil? || chunk.empty?
        rescue EOFError
          nil
        end

      end
    end
  end
end
