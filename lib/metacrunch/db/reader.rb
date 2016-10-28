require "metacrunch/db"

module Metacrunch
  class Db::Reader

    def initialize(database_connection_or_url, dataset_proc, options = {})
      @rows_per_fetch = options.delete(:rows_per_fetch) || 1000

      @db = if database_connection_or_url.is_a?(String)
        Sequel.connect(database_connection_or_url, options)
      else
        database_connection_or_url
      end

      @dataset = dataset_proc.call(@db).unlimited

      unless @dataset.opts[:order]
        raise ArgumentError, "Metacrunch::Db::Reader requires the dataset be ordered."
      end
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      @dataset.paged_each(rows_per_fetch: @rows_per_fetch, strategy: :filter) do |row|
        yield(row)
      end

      self
    end

  end
end
