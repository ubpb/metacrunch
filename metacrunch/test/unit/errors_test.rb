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

  def test_worker_error_names_the_original_exception
    error = Metacrunch::WorkerError.new("Net::Broken", "socket closed")

    assert_equal "Net::Broken: socket closed", error.message
    assert_equal ["Net::Broken", "socket closed"], [error.original_class, error.original_message]
  end

  def test_input_and_output_errors_are_metacrunch_errors
    assert_operator Metacrunch::InputError, :<, Metacrunch::Error
    assert_operator Metacrunch::OutputError, :<, Metacrunch::Error
  end

end
