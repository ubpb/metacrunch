# frozen_string_literal: true

# IO-like inputs that hand out their bytes in odd pieces, for the splitters.
module Inputs

  # Gives the input one byte per call, to cut every tag and terminator.
  class Trickle

    def initialize(string)
      @bytes = string.b
      @position = 0
    end

    def readpartial(_length)
      raise EOFError if @position >= @bytes.bytesize

      @position += 1
      @bytes.byteslice(@position - 1, 1)
    end

  end

  # Gives the input in chunks of a fixed size, whatever is asked for.
  class Chunked

    def initialize(string, size)
      @bytes = string.b
      @size = size
      @position = 0
    end

    def readpartial(_length)
      raise EOFError if @position >= @bytes.bytesize

      @position += @size
      @bytes.byteslice(@position - @size, @size)
    end

  end

  # Fails when read again after its end, where a terminal would wait for
  # more input.
  class EndOnce

    def initialize(string)
      @io = StringIO.new(string)
      @ended = false
    end

    def readpartial(length)
      raise "read again after the end" if @ended

      chunk = @io.read(length)
      return chunk if chunk

      @ended = true
      raise EOFError
    end

  end

  # Has only read, as some IO-like objects do.
  class ReadOnly

    def initialize(string)
      @io = StringIO.new(string)
    end

    def read(length) = @io.read(length)

  end

end
