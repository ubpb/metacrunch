module Metacrunch
  class Job
    require_relative "job/context"

    attr_reader :options

    def self.define(&block)
      raise ArgumentError, "No block given" unless block_given?

      job     = Job.new
      context = Context.new(job)

      context.instance_eval(&block)
      context
    end

    def self.run(context, options = {})
      context.job.run(options)
    end

    def run(options = {})
      @options = options

      run_pre_processes
      run_main_processes
      run_post_processes

      self
    end

    def pre_processes
      @pre_processes ||= []
    end

    def post_processes
      @post_processes ||= []
    end

    def sources
      @sources ||= []
    end

    def destinations
      @destinations ||= []
    end

    def transformations
      @transformations ||= []
    end

  private

    def run_pre_processes
      pre_processes.each(&:call)
    end

    def run_post_processes
      post_processes.each(&:call)
    end

    def run_main_processes
      sources.each do |source|
        source.each do |row| # source implementations are expected to respond to `each`
          transformations.each do |transformation|
            row = transformation.call(row) if row
            break unless row
          end

          next unless row

          destinations.each do |destination|
            destination.write(row) # destination implementations are expected to respond to `write(row)`
          end
        end
      end

      destinations.each(&:close) # destination implementations are expected to respond to `close`
    end

  end
end
