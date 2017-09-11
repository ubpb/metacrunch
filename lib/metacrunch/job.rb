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

    def destination
      @destination
    end

    def destination=(destination)
      ensure_destination!(destination)
      @destination = destination
    end

    def pre_process
      @pre_process
    end

    def pre_process=(callable)
      ensure_callable!(callable)
      @pre_process = callable
    end

    def post_process
      @post_process
    end

    def post_process=(callable)
      ensure_callable!(callable)
      @post_process = callable
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
      run_pre_process
      run_transformations
      run_post_process
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

    def ensure_destination!(object)
      raise ArgumentError, "#{object} doesn't respond to #write." unless object.respond_to?(:write)
      raise ArgumentError, "#{object} doesn't respond to #close." unless object.respond_to?(:close)
    end

    def ensure_callable!(object)
      raise ArgumentError, "#{object} doesn't respond to #call." unless object.respond_to?(:call)
    end

    def run_pre_process
      pre_process.call if pre_process
    end

    def run_post_process
      post_process.call if post_process
    end

    def run_transformations
      if source
        source.each do |data|
          run_transformations_and_write_destinations(data)
        end

        # Run all transformations a last time to flush possible buffers
        run_transformations_and_write_destinations(nil, flush_buffers: true)
      end

      destination.close if destination
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
        destination.write(data) if destination
      end
    end

  end
end
