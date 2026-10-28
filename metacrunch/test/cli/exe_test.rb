# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "pty"
require "shellwords"
require "tmpdir"

class ExeTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  NUMBERS = File.join(ROOT, "test", "fixtures", "jobs", "numbers.rb")
  JOBS = File.join(ROOT, "test", "fixtures", "jobs")
  LIB = File.join(ROOT, "lib")
  EXE = File.join(ROOT, "exe", "metacrunch")

  def test_prints_data_on_stdout_and_logs_on_stderr
    stdout, stderr, status = metacrunch("run", NUMBERS, "--factor", "2", "1", "2")

    assert_equal [0, "2\n4\n"], [status.exitstatus, stdout]
    assert_match(/INFO  ok: read 2, written 2/, stderr)
  end

  def test_exit_codes
    assert_equal 1, metacrunch("run", NUMBERS, "0").last.exitstatus
    assert_equal 3, metacrunch("run", NUMBERS, "--skip-errors", "0", "1").last.exitstatus
    assert_equal 2, metacrunch.last.exitstatus
  end

  def test_interrupt_ends_the_process_by_the_signal
    _stdout, _stderr, status = metacrunch("run", File.join(ROOT, "test", "fixtures", "jobs", "interrupted.rb"))

    assert_predicate status, :signaled?
    assert_equal Signal.list.fetch("INT"), status.termsig
  end

  def test_sigterm_ends_the_process_by_the_signal
    _stdout, _stderr, status = metacrunch("run", File.join(ROOT, "test", "fixtures", "jobs", "terminated.rb"))

    assert_equal Signal.list.fetch("TERM"), status.termsig
  end

  def test_interrupt_keeps_the_data_written_to_stdout
    stdout, stderr, = metacrunch("run", File.join(ROOT, "test", "fixtures", "jobs", "interrupted_output.rb"))

    assert_equal "1\n2\n", stdout
    refute_match(/SignalException|Interrupt \(/, stderr)
  end

  # The filter between the jobs is grep, a tool that is no Ruby: a Ruby
  # filter would inherit RUBYOPT=-rbundler/setup from bundle exec, and
  # `ruby -rjson` then fails wherever the default json gem differs from
  # the bundle's (Ruby head). The status is the last command's only, so
  # stderr goes into every message.
  def test_jobs_chain_through_pipes
    filter = Shellwords.join(["grep", "-E", "\"n\":[135]}"])
    pipeline = [Shellwords.join(command("run", fixture("emit.rb"))), filter,
                Shellwords.join(command("run", fixture("tag.rb")))].join(" | ")
    stdout, stderr, status = Open3.capture3("sh", "-c", pipeline)
    records = stdout.lines.map { JSON.parse(it) }

    assert_predicate status, :success?, stderr
    assert_equal([1, 3, 5], records.map { it["n"] }, stderr)
    assert(records.all? { it["tagged"] }, "untagged records; stderr: #{stderr}")
  end

  def test_a_closed_pipe_ends_the_job_by_sigpipe_and_flushes_other_sinks
    Dir.mktmpdir do |dir|
      rejects = File.join(dir, "rejects.jsonl")
      errors = File.join(dir, "stderr")
      reader, writer = IO.pipe
      pid = Process.spawn(*command("run", "--rejects", rejects, fixture("endless.rb")), out: writer, err: errors)
      writer.close
      first = reader.gets
      reader.close
      _pid, status = Process.wait2(pid)
      reasons = File.readlines(rejects).map { JSON.parse(it).dig("rejection", "reason") }

      assert_equal ["{\"n\":1}\n", Signal.list.fetch("PIPE")], [first, status.termsig]
      assert_empty File.read(errors)
      assert_equal ["Even"], reasons.uniq
    end
  end

  def test_jobs_created_by_generate_run_with_run
    Dir.mktmpdir do |dir|
      Open3.capture3(*command("generate", "job", "jobs/pass.rb"), chdir: dir)
      stdout, stderr, status = Open3.capture3(*command("run", "jobs/pass.rb"), stdin_data: "{\"id\":1}\n", chdir: dir)

      assert_equal [0, "{\"id\":1}\n"], [status.exitstatus, stdout], stderr
      refute File.executable?(File.join(dir, "jobs/pass.rb"))
    end
  end

  def test_shows_progress_on_a_terminal
    output = +""
    PTY.spawn(*command("run", "-o", File::NULL, fixture("slow.rb"))) do |reader, _writer, pid|
      begin
        reader.each_line { output << it }
      rescue Errno::EIO
        nil # Linux: the child closed the terminal
      end
      Process.wait(pid)
    end

    # The display draws every 0.25 s, so on a slow machine at 50 %, with an ETA, instead of at 100 %
    assert_match(/\e\[2K[━─]{20} \d+% \d\d:\d\d:\d\d /, output)
  end

  private

  def command(*)
    [RbConfig.ruby, "-I", LIB, EXE, *]
  end

  def fixture(name) = File.join(JOBS, name)

  def metacrunch(*)
    Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *)
  end

end
