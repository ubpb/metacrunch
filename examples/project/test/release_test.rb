# frozen_string_literal: true

# Tests the orchestration of catalog:release without running the job:
# Metacrunch::Testing.invoke records what the command invokes and answers
# with stubbed results.
#
#   bundle exec ruby -Ilib examples/project/test/release_test.rb

require "minitest/autorun"
require "tmpdir"
require "metacrunch"
require "metacrunch/testing"

class ReleaseTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

  def test_all_files_load_and_every_name_is_unique
    assert_empty PROJECT.load_errors
    assert_empty PROJECT.duplicates
  end

  def test_switches_current_after_a_clean_run
    Dir.mktmpdir do |out|
      run = release(out)

      assert_equal [:ok, ["catalog"]], [run.status, run.invoked.map(&:name)]
      assert_equal ["--output", run.value.to_s], run.invoked.first.argv
      assert_equal File.realpath(run.value), File.realpath(File.join(out, "current"))
    end
  end

  def test_keeps_current_when_records_failed
    Dir.mktmpdir do |out|
      run = release(out, stubs: {"catalog" => :ok_with_failures})

      assert_equal :ok_with_failures, run.status
      refute_path_exists File.join(out, "current")
    end
  end

  private

  def release(out, stubs: {})
    Metacrunch::Testing.invoke(PROJECT, "catalog:release", params: {out:}, stubs:)
  end

end
