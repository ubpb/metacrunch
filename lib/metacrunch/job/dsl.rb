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

    def pre_process(callable)
      @_job.pre_process = callable
    end

    def post_process(callable)
      @_job.post_process = callable
    end

    def transformation_buffer(size)
      @_job.add_transformation_buffer(size)
    end

    def transformation(callable)
      @_job.add_transformation(callable)
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
