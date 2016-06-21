module Metacrunch
  class Db::Writer

    def initialize(database_connection_or_url, dataset_proc, options = {})
      @db = if database_connection_or_url.is_a?(String)
        Sequel.connect(database_connection_or_url, options)
      else
        database_connection_or_url
      end

      @dataset = dataset_proc.call(@db)
    end

    def write(data)
      @dataset.insert(data)
    end

    def close
      @db.disconnect
    end

  end
end