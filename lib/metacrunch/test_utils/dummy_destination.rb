require_relative "../test_utils"

module Metacrunch
  class TestUtils::DummyDestination

    attr_reader :data

    def write(row)
      @write_called = true
      (@data ||= []) << row
    end

    def close
      @close_called = true
    end

  end

  class TestUtils::InvalidDummyDestination
  end
end
