require_relative "../metacrunch"

class Metacrunch::Processor
  def initialize(options = {})
    @options ||= options
  end

  def call(items = [], pipeline = nil)
  end
end
