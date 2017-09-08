module Metacrunch
  class Job::Dsl
    require_relative "dsl/option_support"

    def initialize(job)
      @_job = job
    end

    def source(source)
      @_job.source = source
    end

    def destination(destination)
      @_job.destination = destination
    end

    def pre_process(callable = nil, &block)
      @_job.add_pre_process(callable, &block)
    end

    def post_process(callable = nil, &block)
      @_job.add_post_process(callable, &block)
    end

    def transformation_buffer(size)
      @_job.add_transformation_buffer(size)
    end

    def transformation(callable = nil, &block)
      @_job.add_transformation(callable, &block)
    end

    def options(require_args: false, &block)
      if block_given?
        @_options = OptionSupport.new.register_options(@_job.args, require_args: require_args, &block)
      else
        @_options ||= {}
      end
    end

  end
end
