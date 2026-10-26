# frozen_string_literal: true

module Metacrunch
  module Marc
    module Xml
      # Reads a String in chunks through readpartial. Ox SAX is slow on a
      # String or a StringIO (superlinear in its size) but fast on objects
      # with readpartial; the splitter reads it the same way. Internal.
      class StringSource

        def initialize(string)
          @string = string
          @position = 0
        end

        # A binary chunk of at most length bytes; EOFError at the end, as
        # IO#readpartial.
        def readpartial(length)
          raise EOFError, "end of string reached" if @position >= @string.bytesize

          chunk = @string.byteslice(@position, length).force_encoding(Encoding::BINARY)
          @position += chunk.bytesize
          chunk
        end

      end
    end
  end
end
