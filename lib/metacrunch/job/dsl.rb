module Metacrunch
  class Job::Dsl

    def initialize(job, args: nil)
      @_job = job
      @_args = args
    end

    def run
      @_job.run
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

    def register_options(&block)
      registry = OptionRegistry.new
      yield(registry)

      OptionParser.new do |parser|
        parser.banner = "Job specific options:"

        registry.each do |key, opt_def|
          options[key] = opt_def[:default]
          parser.on(*opt_def[:args]) do |value|
            options[key] = value
          end
        end
      end.parse(@_args)
    end

    def options
      @_options ||= {}
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

    class OptionRegistry

      def add(name, *args, default:)
        options[name.to_sym] = {
          args: args,
          default: default
        }
      end

      def each(&block)
        options.each(&block)
      end

    private

      def options
        @options ||= {}
      end
    end

  end
end
