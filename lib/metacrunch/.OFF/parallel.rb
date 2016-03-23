module Metacrunch
  class Parallel

    module DSL
      def parallel(enumerable, options = {}, &block)
        Parallel.each(enumerable, options, &block)
      end
    end

    def self.each(enumerable, options = {}, &block)
      self.new(enumerable, options, &block).call
    end

    def initialize(enumerable, options = {}, &block)
      @enumerable          = enumerable
      @callable            = block
      @no_of_procs         = options[:in_processes].to_i
      @on_process_finished = options[:on_process_finished] || -> {}

      unless block_given?
        raise ArgumentError, "you must provide a block"
      end

      unless @enumerable.respond_to?(:each)
        raise ArgumentError, "enumerable must respond to each"
      end

      unless @on_process_finished.respond_to?(:call)
        raise ArgumentError, "on_process_finished must respond to call"
      end
    end

    def call
      @enumerable.each do |_value|
        if @no_of_procs <= 1
          @callable.call(_value)
          @on_process_finished.call
        else
          fork_process { @callable.call(_value) }

          if processes_limit_reached?
            wait_for_some_process_to_terminate
            @on_process_finished.call
          end
        end
      end
    ensure
      Process.waitall.each { @on_process_finished.call }
    end

  private

    def fork_process(&block)
      (@pids ||= []).push(fork(&block))
    end

    def processes_limit_reached?
      (@pids || []).length >= @no_of_procs
    end

    def wait_for_some_process_to_terminate
      pid_of_finished_process = Process.wait
      @pids.delete(pid_of_finished_process)
    end

  end
end
