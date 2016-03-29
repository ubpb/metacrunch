module Metacrunch
  class Job::Context

    attr_reader :job

    def initialize(job)
      @job = job
    end

    def options
      @job.options
    end

    def source(source)
      @job.sources << source if source
    end

    def destination(destination)
      @job.destinations << destination if destination
    end

    def pre_process(callable = nil, &block)
      add_callable_or_block(@job.pre_processes, callable, &block)
    end

    def post_process(&block)
      @job.post_processes << block if block_given?
    end

    def transformation(&block)
      @job.transformations << block if block_given?
    end

  private

    def add_callable_or_block(array, callable, &block)
      if block_given?
        array << block
      elsif callable
        array << callable
      end
    end

  end
end
