module Metacrunch
  class Job::Dsl::Helper

    def buffer(id, row, size: 1)
      buffer = buffers[id] ||= []
      buffer << row

      if buffer.count >= size
        buffers[id] = []
        buffer
      end
    end

  private

    def buffers
      @buffers ||= {}
    end

  end
end
