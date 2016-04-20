module Metacrunch
  class Job::Dsl
    require_relative "dsl/helper"
    require_relative "dsl/dependency_support"
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

    def dependencies(&block)
      raise ArgumentError, "Block needed" unless block_given?
      DependencySupport.new(install: @_job.install_dependencies, &block)
    end

    def options(&block)
      if block_given?
        @_options = OptionSupport.new.register_options(@_job.args, &block)
      else
        @_options ||= {}
      end
    end

    def helper
      @_helper ||= Helper.new
    end

  end
end
