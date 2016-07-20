require "metacrunch/db"

module Metacrunch
  class Db::Reader
    include Metacrunch::ParallelProcessableReader

    def initialize(database_connection_or_url, dataset_proc, options = {})
      @rows_per_fetch = options.delete(:rows_per_fetch) || 1000

      @db = if database_connection_or_url.is_a?(String)
        Sequel.connect(database_connection_or_url, options)
      else
        database_connection_or_url
      end

      @dataset = dataset_proc.call(@db).unlimited
      @total_numbers_of_records = @dataset.count

      unless @dataset.opts[:order]
        raise ArgumentError, "Metacrunch::Db::Reader requires the dataset be ordered."
      end
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      @db.transaction do
        offset = (-number_of_processes * @rows_per_fetch) + (process_index * @rows_per_fetch)

        loop do
          offset = offset + (number_of_processes * @rows_per_fetch)

          @dataset.limit(@rows_per_fetch).offset(offset).each do |row|
            yield(row)
          end

          break if offset + @rows_per_fetch >= @total_numbers_of_records
        end
      end

      self
    end

  end
end
