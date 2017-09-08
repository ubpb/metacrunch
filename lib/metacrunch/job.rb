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

    def source
      @source
    end

    def source=(source)
      ensure_source!(source)
      @source = source
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

    def ensure_source!(object)
      raise ArgumentError, "#{object} doesn't respond to #each." unless object.respond_to?(:each)
    end

    def ensure_callable!(object)
      raise ArgumentError, "#{object} doesn't respond to #call." unless object.respond_to?(:call)
    end

    def ensure_destination!(object)
      raise ArgumentError, "#{object} doesn't respond to #write." unless object.respond_to?(:write)
      raise ArgumentError, "#{object} doesn't respond to #close." unless object.respond_to?(:close)
    end

    def run_pre_processes
      pre_processes.each(&:call)
    end

    def run_post_processes
      post_processes.each(&:call)
    end

    def run_transformations
      if source
        source.each do |data|
          run_transformations_and_write_destinations(data)
        end

        # Run all transformations a last time to flush possible buffers
        run_transformations_and_write_destinations(nil, flush_buffers: true)
      end

      # destination implementations are expected to respond to `close`
      destinations.each(&:close)
    end

    def run_transformations_and_write_destinations(data, flush_buffers: false)
      transformations.each do |transformation|
        if transformation.is_a?(Buffer)
          if data.present?
            data = transformation.buffer(data)
            data = transformation.flush if flush_buffers
          else
            data = transformation.flush
          end
        else
          data = transformation.call(data) if data.present?
        end
      end

      if data.present?
        destinations.each do |destination|
          destination.write(data) # destinations are expected to respond to `write(data)`
        end
      end
    end

  end
end
