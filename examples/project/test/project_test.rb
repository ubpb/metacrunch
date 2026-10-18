# frozen_string_literal: true

require_relative "test_helper"

# Fails for a file of the project that does not load and for a name that
# is declared twice.
class ProjectTest < Minitest::Test

  def test_all_files_load_and_every_name_is_unique
    assert_empty PROJECT.load_errors
    assert_empty PROJECT.duplicates
  end

end
