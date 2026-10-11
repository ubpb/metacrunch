# frozen_string_literal: true

require "test_helper"

class OverrideTest < Minitest::Test

  include Override

  module Answer

    def self.value = 1

  end

  def test_replaces_and_restores_a_method_without_warnings
    seen = nil
    _stdout, stderr = capture_io do
      verbose = $VERBOSE
      $VERBOSE = true
      seen = override(Answer, :value, -> { 2 }) { Answer.value }
    ensure
      $VERBOSE = verbose
    end

    assert_equal [2, 1], [seen, Answer.value]
    assert_empty stderr
  end

end
