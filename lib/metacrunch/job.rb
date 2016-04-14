module Metacrunch
  class Job
    require_relative "job/dsl"

    attr_reader :builder

    class << self
      def define(file_content = nil, filename: nil, args: nil, install_dependencies: false, &block)
        self.new(file_content, filename: filename, args: args, install_dependencies: install_dependencies, &block)
      end
    end

    def initialize(file_content = nil, filename: nil, args: nil, install_dependencies: false, &block)
      @builder = Dsl.new(self, args: args, install_dependencies: install_dependencies)

      if file_content
        @builder.instance_eval(file_content, filename || "")
      else
        raise ArgumentError, "No block given" unless block_given?
        @builder.instance_eval(&block)
      end
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

    def run
      run_pre_processes
      run_transformations
      run_post_processes

      self
    end

  private

    def run_pre_processes
      pre_processes.each(&:call)
    end

    def run_post_processes
      post_processes.each(&:call)
    end

    def run_transformations
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
