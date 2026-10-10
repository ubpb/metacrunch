# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test

  def test_step_error_names_step_record_and_cause
    error = Metacrunch::StepError.new(step: "map#2", record_id: "rec1", position: 5, error: KeyError.new("boom"))

    assert_equal "step map#2 failed at position 5 (id rec1): KeyError: boom", error.message
    assert_equal ["map#2", "rec1", 5], [error.step, error.record_id, error.position]
  end

  def test_step_error_without_record_id
    error = Metacrunch::StepError.new(step: "map#2", record_id: nil, position: 5, error: KeyError.new("boom"))

    assert_equal "step map#2 failed at position 5: KeyError: boom", error.message
  end

end
