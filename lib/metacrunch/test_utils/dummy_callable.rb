require_relative "../test_utils"

module Metacrunch
  class TestUtils::DummyCallable

    def call(*args)
      @call_called = true
    end

  end

  class TestUtils::DummyNonCallable
  end
end
