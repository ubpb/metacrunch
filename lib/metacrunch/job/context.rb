module Metacrunch
  class Job::Context

    def initialize(job)
      @_job = job
    end

    def run
      @_job.run
    end

    def source(source)
      @_job.sources << source if source
    end

    def destination(destination)
      @_job.destinations << destination if destination
    end

    def pre_process(callable = nil, &block)
      add_callable_or_block(@_job.pre_processes, callable, &block)
    end

    def post_process(callable = nil, &block)
      add_callable_or_block(@_job.post_processes, callable, &block)
    end

    def transformation(callable = nil, &block)
      add_callable_or_block(@_job.transformations, callable, &block)
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
