module Metacrunch
  class Job::Dsl
    require_relative "dsl/options"

    def initialize(job)
      @_job = job
    end

    def source(source)
      @_job.source = source
    end

    def destination(destination)
      @_job.destination = destination
    end

    def pre_process(callable)
      @_job.pre_process = callable
    end

    def post_process(callable)
      @_job.post_process = callable
    end

    def transformation(callable, buffer_size: nil, buffer: nil)
      @_job.add_transformation(callable, buffer_size: buffer_size, buffer: buffer)
    end

    def options(require_args: false, &block)
      if block_given?
        @_options = Options.new(require_args: require_args, &block).options
      else
        @_options ||= {}
      end
    end

  end
end
