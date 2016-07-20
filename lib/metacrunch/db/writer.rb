require "metacrunch/db"

module Metacrunch
  class Db::Writer

    def initialize(database_connection_or_url, dataset_proc, options = {})
      @use_upsert          = options.delete(:use_upsert)          || false
      @id_key              = options.delete(:id_key)              || :id
      @isolation_level     = options.delete(:isolation_level)     || :repeatable
      @transaction_retries = options.delete(:transaction_retries) || 5

      @db = if database_connection_or_url.is_a?(String)
        Sequel.connect(database_connection_or_url, options)
      else
        database_connection_or_url
      end

      @dataset = dataset_proc.call(@db)
    end

    def write(data)
      if data.is_a?(Array)
        @db.transaction(isolation: @isolation_level, num_retries: @transaction_retries) do
          data.each{|d| insert_or_upsert(d) }
        end
      else
        insert_or_upsert(data)
      end
    end

    def close
      @db.disconnect
    end

  private

    def insert_or_upsert(data)
      @use_upsert ? upsert(data) : insert(data)
    end

    def insert(data)
      @dataset.insert(data) if data
    end

    def upsert(data)
      if data
        rec = @dataset.where(@id_key => data[@id_key])
        if 1 != rec.update(data)
          insert(data)
        end
      end
    end

  end
end
