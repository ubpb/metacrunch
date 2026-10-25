# frozen_string_literal: true

require "test_helper"

class FilesTest < Minitest::Test

  Files = Metacrunch::Files

  def test_paths
    assert Files.path?("a.jsonl")
    assert Files.path?(Pathname("a.jsonl"))
  end

  def test_dash_and_ios_are_no_paths
    refute Files.path?("-")
    refute Files.path?(StringIO.new)
  end

  def test_names_of_paths_and_files
    File.open(__FILE__) { assert_equal __FILE__, Files.name(it) }

    assert_equal "a/b.jsonl", Files.name(Pathname("a/b.jsonl"))
    assert_equal "-", Files.name("-")
  end

  def test_stdin_and_stdout_are_named_dash
    assert_equal "-", Files.name($stdin)
    assert_equal "-", Files.name($stdout)
  end

  def test_other_ios_are_named_by_their_class
    assert_equal "StringIO", Files.name(StringIO.new)
    assert_equal "StringIO", Files.name(Class.new(StringIO).new)
  end

  def test_reasons_are_the_system_text_in_lower_case
    assert_equal "no such file or directory", Files.reason(Errno::ENOENT.new("a.jsonl"))
    assert_equal "no space left on device", Files.reason(Errno::ENOSPC.new)
    assert_match(/\Aunknown error/, Files.reason(SystemCallError.new("x", 99_999)))
  end

end
