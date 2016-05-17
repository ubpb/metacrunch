require "sequel"

module Metacrunch
  class Db
    require_relative "db/reader"
    require_relative "db/writer"
  end
end
