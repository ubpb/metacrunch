module Metacrunch
  class Job
    require_relative "job/dsl"
    require_relative "job/buffer"

    attr_reader :builder, :args

    class << self
      def define(file_content = nil, filename: nil, args: nil, &block)
        self.new(file_content, filename: filename, args: args, &block)
      end
    end

    def initialize(file_content = nil, filename: nil, args: nil, &block)
      @builder = Dsl.new(self)
      @args = args

      if file_content
        @builder.instance_eval(file_content, filename || "")
      elsif block_given?
        @builder.instance_eval(&block)
      end
    end

    def sources
      @sources ||= []
    end

    def add_source(source)
      ensure_source!(source)
      sources << source
    end

    def destinations
      @destinations ||= []
    end

    def add_destination(destination)
      ensure_destination!(destination)
      destinations << destination
    end

    def pre_processes
      @pre_processes ||= []
    end

    def add_pre_process(callable = nil, &block)
      add_callable_or_block(pre_processes, callable, &block)
    end

    def post_processes
      @post_processes ||= []
    end

    def add_post_process(callable = nil, &block)
      add_callable_or_block(post_processes, callable, &block)
    end

    def transformations
      @transformations ||= []
    end

    def add_transformation(callable = nil, &block)
      add_callable_or_block(transformations, callable, &block)
    end

    def add_transformation_buffer(size)
      transformations << Metacrunch::Job::Buffer.new(size)
    end

    def run
      run_pre_processes
      run_transformations
      run_post_processes
      self
    end

  private

    def add_callable_or_block(array, callable, &block)
      if block_given?
        array << block
      elsif callable
        ensure_callable!(callable)
        array << callable
      end
    end

    def ensure_callable!(object)
      raise ArgumentError, "#{object} does't respond to #call." unless object.respond_to?(:call)
    end

    def ensure_source!(object)
      raise ArgumentError, "#{object} does't respond to #each." unless object.respond_to?(:each)
    end

    def ensure_destination!(object)
      raise ArgumentError, "#{object} does't respond to #write." unless object.respond_to?(:write)
      raise ArgumentError, "#{object} does't respond to #close." unless object.respond_to?(:close)
    end

    def run_pre_processes
      pre_processes.each(&:call)
    end

    def run_post_processes
      post_processes.each(&:call)
    end

    def run_transformations
      sources.each do |source|
        # sources are expected to respond to `each`
        source.each do |row|
          _run_transformations(row)
        end

        # Run all transformations a last time to flush possible buffers
        _run_transformations(nil, flush_buffers: true)
      end

      # destination implementations are expected to respond to `close`
      destinations.each(&:close)
    end

    def _run_transformations(row, flush_buffers: false)
      transformations.each do |transformation|
        row = if transformation.is_a?(Buffer)
          if flush_buffers
            transformation.flush
          else
            transformation.buffer(row)
          end
        else
          transformation.call(row) if row
        end

        break unless row
      end

      if row
        destinations.each do |destination|
          # destinations are expected to respond to `write(row)`
          destination.write(row)
        end
      end
    end

  end
end
