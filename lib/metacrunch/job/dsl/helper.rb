module Metacrunch
  class Job::Dsl::Helper

    def buffer(id, data, size: 1)
      buffer = buffers[id] ||= []
      buffer << data

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
