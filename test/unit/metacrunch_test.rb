# frozen_string_literal: true

require "test_helper"

class MetacrunchTest < Minitest::Test

  def setup
    Metacrunch.logger = nil
  end

  def teardown
    Metacrunch.logger = nil
  end

  def test_default_logger_writes_to_stderr_not_stdout
    stdout, stderr = capture_io { Metacrunch.logger.info("hello") }

    assert_empty stdout
    assert_match(/INFO  hello$/, stderr)
  end

end
