# frozen_string_literal: true

require "test_helper"
require "open3"

class ExeProjectTest < Minitest::Test

  include CredentialsHelper

  ROOT = File.expand_path("../..", __dir__)
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil}.freeze

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "lib/marker_sink.rb" => <<~RUBY,
      # Writes each record on a line of its own at once, and "closed" when
      # it is closed.
      class MarkerSink

        def initialize(path)
          @path = path
        end

        def open(_context)
          @file = File.open(@path, "w")
          @file.sync = true
        end

        def write(record)
          @file.puts(record)
        end

        def close
          @file.puts("closed")
          @file.close
        end

      end
    RUBY
    "jobs/numbers.rb" => <<~RUBY,
      Metacrunch.job "numbers" do
        params do
          param :skip, :bool, default: false
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        map { 100 / it }
        on_failure(params.skip ? :skip : :abort)
      end
    RUBY
    "jobs/forever.rb" => <<~RUBY,
      require_relative "../lib/marker_sink"

      Metacrunch.job "forever" do
        params { param :output, String, required: true }

        source((1..).lazy)
        sink MarkerSink.new(params.output)
      end
    RUBY
    "commands/note.rb" => <<~RUBY,
      Metacrunch.command "note" do
        params { args :text, min: 1, max: 1 }

        run { File.write(root.join("note.txt"), params.text.first) }
      end
    RUBY
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain" do
        params do
          param :skip, :bool, default: false
          args :numbers
        end

        run do
          invoke "numbers", params: {skip: params.skip, numbers: params.numbers}
          invoke "note", params: {text: "done"}
        end
      end
    RUBY
    "commands/watch.rb" => <<~RUBY
      Metacrunch.command "watch" do
        params { args :output, min: 1, max: 1 }

        run do
          invoke "forever", params: {output: params.output.first}
          invoke "note", params: {text: "after"}
        end
      end
    RUBY
  }.freeze

  # A command shipped by a gem, outside the project; it reads a credential
  # and invokes a job of the project that reads the same credential.
  GEM_COMMAND = <<~'RUBY'
    Metacrunch.command "secret:check" do
      params { secret :api_key, String, default: {credential: "catalog.api_key"} }

      run do
        logger.info("command: #{params.api_key.reverse}")
        invoke "secret"
      end
    end
  RUBY

  def test_a_chain_from_a_subdirectory_exits_with_ok_aborted_and_failures
    in_project do |root|
      jobs = File.join(root, "jobs")
      ok = metacrunch("run", "chain", "4", chdir: jobs, home: root)
      noted = File.read(File.join(root, "note.txt"))
      File.delete(File.join(root, "note.txt"))
      aborted = metacrunch("run", "chain", "0", chdir: jobs, home: root)
      partial = metacrunch("run", "chain", "--skip", "0", "4", chdir: jobs, home: root)

      assert_equal([0, 1, 3], [ok, aborted, partial].map { it.last.exitstatus })
      assert_equal ["25\n", "done", "25\n"], [ok.first, noted, partial.first]
      assert_match(/ERROR numbers aborted: Metacrunch::StepError/, aborted[1])
    end
  end

  def test_sigterm_during_an_invoked_job_closes_its_sink_and_ends_the_chain
    assert_equal [Signal.list.fetch("TERM"), "closed", false], interrupt_watch("TERM")
  end

  def test_ctrl_c_during_an_invoked_job_closes_its_sink_and_ends_the_chain
    assert_equal [Signal.list.fetch("INT"), "closed", false], interrupt_watch("INT")
  end

  def test_production_credentials_reach_a_gem_command_and_the_job_it_invokes
    in_tmpdir do |dir|
      root = File.join(dir, "project")
      glob = File.join(dir, "gem", "commands", "*.rb")
      write_ruby(dir, "gem/commands/secret.rb", GEM_COMMAND)
      write_ruby(root, "Metacrunchfile", "Metacrunch.load_files #{glob.inspect}, \"jobs/*.rb\"\n")
      write_file(root, "jobs/secret.rb", SECRET_JOB.sub("Metacrunch.job do", "Metacrunch.job \"secret\" do"))
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      jobs = File.join(root, "jobs")
      stdout, stderr, status = metacrunch("run", "-e", "production", "secret:check", chdir: jobs, home: dir)

      assert_equal [0, "\"#{SECRET.reverse}\"\n" * 2], [status.exitstatus, stdout], stderr
      assert_match(/INFO  command: #{SECRET.reverse}/, stderr)
    end
  end

  private

  # Sends signal to the command watch while its invoked job runs. Returns
  # the signal that ended the process, the last line the job's sink wrote
  # and whether the command went on after the job.
  def interrupt_watch(signal)
    in_project do |root|
      output = File.join(root, "forever.txt")
      pid = Process.spawn(env(root), *command("run", "watch", output), chdir: root, out: File::NULL, err: File::NULL)
      status = nil
      begin
        wait_for { File.size?(output) }
        Process.kill(signal, pid)
        _pid, status = Process.wait2(pid)
      ensure
        stop(pid) unless status
      end
      [status.termsig, File.readlines(output, chomp: true).last, File.exist?(File.join(root, "note.txt"))]
    end
  end

  # Yields the root of a temporary project with FILES.
  def in_project
    in_tmpdir do |root|
      FILES.each { |path, code| write_ruby(root, path, code) }
      yield root
    end
  end

  def write_ruby(root, path, code) = write_file(root, path, "# frozen_string_literal: true\n\n#{code}")

  def metacrunch(*, chdir:, home:)
    Open3.capture3(env(home), *command(*), chdir:)
  end

  def command(*args)
    [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *args]
  end

  # HOME points into the test's directory, so ~/.metacrunch is never read.
  def env(home) = CLEAN_ENV.merge("HOME" => home)

  def wait_for(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  # Kills and reaps pid, which the test has not reaped yet, so a failing
  # test leaves no endless process behind.
  def stop(pid)
    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

end
