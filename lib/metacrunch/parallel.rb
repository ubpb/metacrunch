module Metacrunch
  class Parallel

    def initialize(enumerator, &block)
      @callable   = block
      @enumerator = enumerator
    end

    def call(options = {})
      number_of_processes = options[:in_processes] || 0
      options[:on_process_finished] ||= -> {}

      begin
        @enumerator.each do |enumerator_value|
          if number_of_processes == 0
            @callable.call(enumerator_value)
            options[:on_process_finished].call
          else
            fork_process do
              @callable.call(enumerator_value)
            end

            if processes_limit_reached?(number_of_processes)
              wait_for_some_process_to_terminate
              options[:on_process_finished].call
            end
          end
        end
      ensure
        Process.waitall.each { options[:on_process_finished].call }
      end
    end

  private

    def fork_process(&block)
      (@pids ||= []).push(fork(&block))
    end

    def processes_limit_reached?(number_of_processes)
      (@pids || []).length >= number_of_processes
    end

    def wait_for_some_process_to_terminate
      pid_of_finished_process = Process.wait
      @pids.delete(pid_of_finished_process)
    end

  end
end
