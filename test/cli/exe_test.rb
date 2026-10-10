# frozen_string_literal: true

require "test_helper"
require "open3"

class ExeTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  NUMBERS = File.join(ROOT, "test", "fixtures", "jobs", "numbers.rb")

  def test_prints_data_on_stdout_and_logs_on_stderr
    stdout, stderr, status = metacrunch(NUMBERS, "--factor", "2", "1", "2")

    assert_equal [0, "2\n4\n"], [status.exitstatus, stdout]
    assert_match(/INFO  ok: read 2, written 2/, stderr)
  end

  def test_exit_codes
    assert_equal 1, metacrunch(NUMBERS, "0").last.exitstatus
    assert_equal 3, metacrunch(NUMBERS, "--skip-errors", "0", "1").last.exitstatus
    assert_equal 2, metacrunch.last.exitstatus
  end

  def test_interrupt_ends_the_process_by_the_signal
    _stdout, _stderr, status = metacrunch(File.join(ROOT, "test", "fixtures", "jobs", "interrupted.rb"))

    assert_predicate status, :signaled?
    assert_equal Signal.list.fetch("INT"), status.termsig
  end

  def test_sigterm_ends_the_process_by_the_signal
    _stdout, _stderr, status = metacrunch(File.join(ROOT, "test", "fixtures", "jobs", "terminated.rb"))

    assert_equal Signal.list.fetch("TERM"), status.termsig
  end

  def test_interrupt_keeps_the_data_written_to_stdout
    stdout, stderr, = metacrunch(File.join(ROOT, "test", "fixtures", "jobs", "interrupted_output.rb"))

    assert_equal "1\n2\n", stdout
    refute_match(/SignalException|Interrupt \(/, stderr)
  end

  private

  def metacrunch(*)
    Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *)
  end

end
