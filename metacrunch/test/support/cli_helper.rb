# frozen_string_literal: true

require "metacrunch/cli"

# Runs Metacrunch::Cli in-process with injected streams. Fixture sinks that
# print to $stdout are captured as well.
module CliHelper

  JOBS = File.expand_path("../fixtures/jobs", __dir__)

  # Stdin that claims to be a terminal.
  class TerminalInput < StringIO

    def tty? = true

  end

  # stderr that claims to be a terminal.
  class TerminalOutput < StringIO

    def tty? = true

  end

  # Returns [exit code, stdout, stderr]. stderr: an IO to use instead of a
  # captured one, e.g. a TerminalOutput.
  def cli(*args, stdin: "", env: {}, stderr: nil)
    code = nil
    input = stdin.is_a?(String) ? StringIO.new(stdin) : stdin
    stdout, captured = capture_io do
      code = Metacrunch::Cli.new(stdin: input, stdout: $stdout, stderr: stderr || $stderr, env:).run(args)
    end
    [code, stdout, stderr ? stderr.string : captured]
  end

  def job(name) = File.join(JOBS, name)

end
