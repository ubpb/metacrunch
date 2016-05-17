module Metacrunch
  class Db::Reader

    def initialize(url, dataset_proc, options = {})
      @rows_per_fetch = options.delete(:rows_per_fetch) || 1000
      @db = Sequel.connect(url, options)
      @dataset = dataset_proc.call(@db)
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      @dataset.paged_each(rows_per_fetch: @rows_per_fetch) do |row|
        yield(row)
      end

      self
    end

  end
end
