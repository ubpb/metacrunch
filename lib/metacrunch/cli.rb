# frozen_string_literal: true

require "optparse"
require_relative "../metacrunch"
require_relative "progress"
require_relative "trace"
require_relative "cli/run_options"
require_relative "cli/command"
require_relative "cli/job_command"
require_relative "cli/run"
require_relative "cli/check"
require_relative "cli/trace"
require_relative "cli/new"
require_relative "cli/credentials"

module Metacrunch
  # The command line interface. Dispatches to a command by the first
  # argument; a job file there is short for `run`. #run returns the exit
  # code, exe/metacrunch exits with it.
  class Cli

    EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3}.freeze
    COMMANDS = {
      "run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand, "new" => NewCommand,
      "credentials" => CredentialsCommand
    }.freeze

    # The streams and environment the commands use instead of globals.
    Streams = Data.define(:stdin, :stdout, :stderr, :env)

    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV)
      @streams = Streams.new(stdin:, stdout:, stderr:, env:)
    end

    def run(argv)
      first, *rest = argv
      case first
      when nil then usage_error("no command or job file given")
      when "-h", "--help" then show(usage)
      when "--version" then show(VERSION)
      when "help" then help(rest.first)
      when *COMMANDS.keys then command(first).run(rest)
      else other(first, argv)
      end
    end

    private

    # An option or a job file (short for run).
    def other(first, argv)
      return usage_error("unknown option #{first}") if first.start_with?("-")
      return command("run").run(argv) if File.file?(first)

      usage_error("unknown command or job file: #{first}")
    end

    def help(name)
      return show(usage) if name.nil? || name == "help"
      return usage_error("unknown command #{name}") unless COMMANDS.key?(name)

      command(name).run(["--help"])
    end

    def command(name)
      COMMANDS.fetch(name).new(@streams)
    end

    def usage
      width = [*COMMANDS.keys, "help"].map(&:size).max
      commands = COMMANDS.map { |name, command| "  #{name.ljust(width)} #{command::SUMMARY}" }
      commands << "  #{"help".ljust(width)} Show the help of a command"
      <<~TEXT
        Usage: metacrunch COMMAND [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
               metacrunch JOB_FILE [JOB_PARAMS...] [ARGS...]    (same as run)

        Commands:
        #{commands.join("\n")}

        Options:
          -h, --help     Show this help
              --version  Show the version
      TEXT
    end

    def show(text)
      @streams.stdout.puts(text)
      EXIT_CODES[:ok]
    end

    def usage_error(message)
      @streams.stderr.puts("Error: #{message}", "Run \"metacrunch --help\" for usage.")
      EXIT_CODES[:usage]
    end

  end
end
