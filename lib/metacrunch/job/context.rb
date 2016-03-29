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

    def pre_process(&block)
      @job.pre_processes << block if block_given?
    end

    def post_process(&block)
      @job.post_processes << block if block_given?
    end

    def transformation(&block)
      @job.transformations << block if block_given?
    end

  end
end
