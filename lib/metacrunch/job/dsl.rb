module Metacrunch
  class Job::Dsl
    require_relative "dsl/bundler_support"
    require_relative "dsl/option_support"

    def initialize(job)
      @_job = job
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
