require_relative "../test_utils"

module Metacrunch
  class TestUtils::DummySource

    def initialize(count_until: 10)
      @count_until = count_until
    end

    def each
      @each_called = true

      (1..@count_until).each do |number|
        yield({number: number})
      end
    end

  end

  class TestUtils::InvalidDummySource
  end
end
