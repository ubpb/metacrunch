module Metacrunch
  class Job::Buffer

    def initialize(size_or_proc)
      @size_or_proc = size_or_proc
      @buffer = []

      if @size_or_proc.is_a?(Numeric) && @size_or_proc <= 0
        raise ArgumentError, "Buffer size must be a posive number greater that 0."
      end
    end

    def buffer(data)
      @buffer << data

      case @size_or_proc
      when Numeric
        flush if @buffer.count >= @size_or_proc.to_i
      when Proc
        flush if @size_or_proc.call == true
      end
    end

    def flush
      @buffer
    ensure
      @buffer = []
    end

  end
end
