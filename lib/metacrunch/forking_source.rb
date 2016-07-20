module Metacrunch
  module ForkingSource

    def set_forking_options(total_numbers_of_processes: 1, process_index: 0)
      raise ArgumentError, "total_numbers_of_processes must be >= 1" if total_numbers_of_processes < 1
      raise ArgumentError, "process_index must be >= 0" if process_index < 0

      @total_numbers_of_processes = total_numbers_of_processes
      @process_index = process_index
    end

    def total_numbers_of_processes
      @total_numbers_of_processes || 1
    end

    def process_index
      @process_index || 0
    end

  end
end
