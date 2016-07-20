module Metacrunch
  module ParallelProcessableReader

    def set_parallel_process_options(number_of_processes: 1, process_index: 0)
      raise ArgumentError, "number_of_processes must be >= 1" if number_of_processes < 1
      raise ArgumentError, "process_index must be >= 0" if process_index < 0

      @number_of_processes = number_of_processes
      @process_index = process_index
    end

    def number_of_processes
      @number_of_processes || 1
    end

    def process_index
      @process_index || 0
    end

  end
end
