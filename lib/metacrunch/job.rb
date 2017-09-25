module Metacrunch
  class Job
    require_relative "job/dsl"
    require_relative "job/buffer"

    attr_reader :dsl

    class << self
      def define(file_content = nil, &block)
        self.new(file_content, &block)
      end
    end

    def initialize(file_content = nil, &block)
      @dsl = Dsl.new(self)

      if file_content
        @dsl.instance_eval(file_content, "Check your metacrunch Job at Line")
      elsif block_given?
        @dsl.instance_eval(&block)
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

    def add_transformation(callable, buffer_size: nil)
      ensure_callable!(callable)

      if buffer_size && buffer_size.to_i > 0
        transformations << Metacrunch::Job::Buffer.new(buffer_size)
      end

      transformations << callable
    end

    def run
      run_pre_process

      if source
        # Run transformation for each data object available in source
        source.each do |data|
          data = run_transformations(data)
          write_destination(data)
        end

        # Run all transformations a last time to flush existing buffers
        data = run_transformations(data = nil, flush_buffers: true)
        write_destination(data)

        # Close destination
        destination.close if destination
      end

      run_post_process

      self
    end

  private

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

    def run_transformations(data, flush_buffers: false)
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

      data
    end

    def write_destination(data)
      destination.write(data) if destination
    end

  end
end
