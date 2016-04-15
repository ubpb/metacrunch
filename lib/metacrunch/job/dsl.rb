module Metacrunch
  class Job::Dsl
    require_relative "dsl/bundler_support"
    require_relative "dsl/option_support"

    def initialize(job)
      @_job = job
    end

    def source(source)
      @_job.add_source(source)
    end

    def destination(destination)
      @_job.add_destination(destination)
    end

    def pre_process(callable = nil, &block)
      @_job.add_pre_process(callable, &block)
    end

    def post_process(callable = nil, &block)
      @_job.add_post_process(callable, &block)
    end

    def transformation(callable = nil, &block)
      @_job.add_transformation(callable, &block)
    end

    def dependencies(&gemfile)
      BundlerSupport.new(install: @_job.install_dependencies, &gemfile)
      exit(0) if @_job.install_dependencies
    end

    def options(&block)
      if block_given?
        @_options = OptionSupport.new.register_options(@_job.args, &block)
      else
        @_options ||= {}
      end
    end

    def row_buffer(id, row, size: 1)
      buffer = row_buffers[id] ||= []
      buffer << row

      if buffer.count >= size
        row_buffers[id] = []
        buffer
      end
    end

    def row_buffers
      @__row_buffers ||= {}
    end

  end
end
