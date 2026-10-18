# frozen_string_literal: true

require "optparse"
require_relative "../metacrunch"
require_relative "progress"
require_relative "trace"
require_relative "credentials/editor"
require_relative "generators"
require_relative "cli/project_lookup"
require_relative "cli/command"
require_relative "cli/job_command"
require_relative "cli/run"
require_relative "cli/check"
require_relative "cli/trace"
require_relative "cli/new"
require_relative "cli/credentials"

module Metacrunch
  # The command line interface. Dispatches to a command by the first
  # argument; a job, transform or command there, by name or file, is short
  # for `run`. #run returns the exit code, exe/metacrunch exits with it.
  class Cli

    EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3}.freeze
    COMMANDS = {
      "run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand, "new" => NewCommand,
      "credentials" => CredentialsCommand
    }.freeze
    # The sections of a project in --help, by the kind they list.
    LISTS = {"Jobs" => Metacrunch::Job, "Transforms" => Metacrunch::Transform,
             "Project commands" => Metacrunch::Command}.freeze

    # The streams and environment the commands use instead of globals.
    Streams = Data.define(:stdin, :stdout, :stderr, :env)

    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV)
      @streams = Streams.new(stdin:, stdout:, stderr:, env:)
      @lookup = ProjectLookup.new
    end

    def run(argv)
      first, *rest = argv
      case first
      when nil then usage_error("no command, job, transform or file given")
      when "-h", "--help" then show(usage)
      when "--version" then show(VERSION)
      when "help" then help(rest.first)
      when *COMMANDS.keys then command(first).run(rest)
      else other(first, argv)
      end
    end

    private

    # An option, or a job, transform or command by name or file: short for
    # run.
    def other(first, argv)
      return usage_error("unknown option #{first}") if first.start_with?("-")
      return command("run").run(argv) if runnable?(first)

      usage_error(unknown(first))
    rescue ProjectError => e
      usage_error(e.message)
    end

    def help(name)
      return show(usage) if name.nil? || name == "help"
      return command(name).run(["--help"]) if COMMANDS.key?(name)
      return command("run").run([name, "--help"]) if runnable?(name)

      usage_error(unknown(name))
    rescue ProjectError => e
      usage_error(e.message)
    end

    # A file given by path; else a name of the project, which wins over a
    # file of that name. Paths never load the project.
    def runnable?(target)
      return File.file?(target) if Names.path?(target)

      project&.include?(target) || File.file?(target)
    end

    def unknown(target)
      return "unknown job, transform, command or file: #{target}" if Names.path?(target)

      hint = project ? project.load_hint : " (no #{Project::FILE} found)"
      "unknown job, transform, command or file: #{target}#{hint}"
    end

    # The project of the working directory. Its files that did not load
    # give warnings on stderr, once per call.
    def project = @lookup.project(Metacrunch.build_logger(@streams.stderr))

    def command(name)
      COMMANDS.fetch(name).new(@streams, @lookup)
    end

    def usage
      width = [*COMMANDS.keys, "help"].map(&:size).max
      commands = COMMANDS.map { |name, command| "  #{name.ljust(width)} #{command::SUMMARY}" }
      commands << "  #{"help".ljust(width)} Show the help of a command, job, transform or file"
      text = <<~TEXT
        Usage: metacrunch COMMAND [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]
               metacrunch NAME|FILE [PARAMS...] [ARGS...]    (same as run)

        Commands:
        #{commands.join("\n")}

        Options:
          -h, --help     Show this help
              --version  Show the version
      TEXT
      [text, *project_help].join("\n")
    end

    # The jobs, transforms and commands of the project and the files that
    # did not load, or the error of the Metacrunchfile. No warnings: the
    # list shows the files.
    def project_help
      project = @lookup.project(nil)
      project ? project_sections(project) : []
    rescue ProjectError => e
      ["Project:\n  #{e.message.lines.first.chomp}\n"]
    end

    def project_sections(project)
      names = project.names
      width = names.map(&:size).max
      kinds = names.group_by { project.declared(it).first.class }
      lists = LISTS.filter_map do |title, kind|
        entries = kinds.fetch(kind, []).map { entry(project, it, width) }
        section("#{title} (#{project.root})", entries) if entries.any?
      end
      errors = project.load_errors.map { |file, error| "  #{project.load_error_summary(file, error)}" }
      [*lists, (section("Not loaded", errors) if errors.any?)].compact
    end

    def section(title, lines) = "#{title}:\n#{lines.join("\n")}\n"

    def entry(project, name, width)
      declarations = project.declared(name)
      desc = declarations.one? ? declarations.first.desc : "(declared more than once, unusable)"
      "  #{name.ljust(width)}  #{desc}".rstrip
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
