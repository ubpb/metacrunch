# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "timeout"
require "tmpdir"

class ExeWorkersTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  JOBS = File.join(ROOT, "test", "fixtures", "jobs")

  def test_workers_write_the_same_files_as_inline
    Dir.mktmpdir do |dir|
      input = File.join(dir, "in.jsonl")
      File.write(input, (1..300).map { record(it) }.join)
      inline = run_sanitize(dir, "inline", input)
      forked = run_sanitize(dir, "forked", input, "-w", "3")

      assert_equal inline, forked
      assert_equal([234, 42, 24], inline.map { it.lines.size })
    end
  end

  def test_a_closed_pipe_ends_the_job_by_sigpipe
    reader, writer = IO.pipe
    pid = Process.spawn(*command("run", "-w", "2", fixture("endless.rb")), out: writer, err: File::NULL,
                                                                           pgroup: true)
    writer.close
    first = reader.gets
    reader.close
    _pid, status = Timeout.timeout(30) { Process.wait2(pid) }

    assert_equal ["{\"n\":1}\n", Signal.list.fetch("PIPE")], [first, status.termsig]
    assert_group_ended(pid)
  end

  def test_sigint_to_the_process_group_ends_the_job_by_sigint
    status, pid = signal_running_job("INT", group: true)

    assert_equal Signal.list.fetch("INT"), status.termsig
    assert_group_ended(pid)
  end

  def test_sigterm_to_the_parent_ends_the_job_by_sigterm
    status, pid = signal_running_job("TERM", group: false)

    assert_equal Signal.list.fetch("TERM"), status.termsig
    assert_group_ended(pid)
  end

  private

  def command(*)
    [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *]
  end

  def fixture(name) = File.join(JOBS, name)

  # Titles of every 7th record are blank, years of every 11th are broken:
  # 42 rejected, 24 failed (multiples of 77 are rejected first), 234 written.
  def record(number)
    title = (number % 7).zero? ? "  " : "Title  #{number} "
    year = (number % 11).zero? ? "x" : "2020"
    "#{JSON.generate({"id" => number, "title" => title, "year" => year})}\n"
  end

  # Runs sanitize.rb and returns its output, rejects and failures files.
  def run_sanitize(dir, name, input, *options)
    files = ["out", "rejects", "errors"].map { File.join(dir, "#{name}.#{it}.jsonl") }
    arguments = ["run", *options, "-i", input, "-o", files[0], "--rejects", files[1], "--failures", files[2]]
    _stdout, stderr, status = Open3.capture3(*command(*arguments, fixture("sanitize.rb")))
    raise "sanitize.rb failed (#{status.exitstatus}): #{stderr}" unless status.exitstatus == 3

    files.map { File.read(it) }
  end

  # Starts endless.rb with two workers in its own process group, waits
  # until the workers run, sends the signal and returns the exit status
  # and the pid, which is also the process group.
  def signal_running_job(signal, group:)
    errors, writer = IO.pipe
    pid = Process.spawn(*command("run", "-v", "-w", "2", "-o", File::NULL, fixture("endless.rb")),
                        err: writer, pgroup: true)
    writer.close
    started = Timeout.timeout(30) { errors.each_line.find { it.include?("started 2 workers") } }
    raise "endless.rb did not start its workers" unless started

    drain = Thread.new { errors.read }
    Process.kill(signal, group ? -pid : pid)
    _pid, status = Timeout.timeout(30) { Process.wait2(pid) }
    drain.join
    [status, pid]
  ensure
    errors&.close
  end

  # No process of the job's process group is left; the workers are in it.
  def assert_group_ended(pgid)
    Process.kill(0, -pgid)

    flunk("a process of the group #{pgid} is left")
  rescue Errno::ESRCH
    pass
  end

end
