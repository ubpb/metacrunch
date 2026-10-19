# frozen_string_literal: true

# Tests the orchestration of catalog:release without running the job:
# Metacrunch::Testing.invoke records what the command invokes and answers
# with stubbed results.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"
require "tmpdir"

class CatalogReleaseCommandTest < Minitest::Test

  def test_switches_current_after_a_clean_run
    Dir.mktmpdir do |out|
      run = release(out)

      assert_equal [:ok, ["catalog"]], [run.status, run.invoked.map(&:name)]
      assert_equal({output: run.value, input: nil}, run.invoked.first.params)
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
