require_relative "../test_utils"

module Metacrunch
  class TestUtils::DummyCallable

    def call(row = nil)
      @call_called = true
    end

  end

  class TestUtils::DummyNonCallable
  end
end
