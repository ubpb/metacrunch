module Metacrunch
  class Job::Buffer

    def initialize(size)
      @size = size
    end

    def buffer(data)
      storage << data
      flush if storage.count >= @size
    end

    def flush
      storage
    ensure
      @buffer = nil
    end

  private

    def storage
      @buffer ||= []
    end

  end
end
