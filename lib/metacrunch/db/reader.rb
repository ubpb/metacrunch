module Metacrunch
  class Db::Reader

    def initialize(url, sql, options = {})
      @db = Sequel.connect(url, options)
      @sql = sql
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      @db[@sql].each(&block)
    end

  end
end
