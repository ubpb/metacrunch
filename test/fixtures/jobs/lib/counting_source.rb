# frozen_string_literal: true

# Source that counts how often it is constructed.
class CountingSource

  class << self

    attr_accessor :constructed

  end

  self.constructed = 0

  def initialize
    self.class.constructed += 1
  end

  def each(&)
    [1].each(&)
  end

end
