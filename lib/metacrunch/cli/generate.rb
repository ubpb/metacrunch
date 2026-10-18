# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch generate: creates a job, transform, command, source or
    # sink with a test, by name in the project or by path anywhere (see
    # Generators::Target). After writing a job, transform or command it
    # loads the project again and tells when the new name is not in it.
    class GenerateCommand < Command

      NAME = "generate"
      SUMMARY = "Create a job, transform, command, source or sink"
      USAGE = "generate KIND [OPTIONS] NAME|PATH"
      HELP = <<~TEXT
        Kinds:
          job        jobs/NAME.rb: reads JSON Lines from stdin and writes them to stdout
          transform  transforms/NAME.rb: steps that jobs use
          command    commands/NAME.rb: a body that invokes jobs and commands
          source     lib/NAME.rb: a class that yields records
          sink       lib/NAME.rb: a class that writes records

        A NAME (catalog:ids) places the file in the project of the working directory,
        with a test in test/. A PATH (tools/fix.rb) places it there, without a test
        unless --test is given.

        Options:
      TEXT

      def initialize(streams, lookup)
        super
        @test = nil
        @desc = nil
        @force = false
      end

      private

      def define_options(parser)
        HELP.each_line(chomp: true) { parser.separator(it) }
        parser.on("--[no-]test", "Create a test (default: for a NAME)") { @test = it }
        parser.on("--desc TEXT", "Description for metacrunch --help (job, transform, command)") { @desc = it }
        parser.on("--force", "Overwrite existing files") { @force = true }
      end

      # Options may stand anywhere.
      def parse(parser, argv) = parser.permute!(argv)

      def execute(argv)
        kind, argument, *rest = argv
        check_arguments(kind, argument, rest)
        root = project&.root unless Names.path?(argument)
        target = Generators::Target.for(kind, argument, cwd: Dir.pwd, root:)
        check_desc(target)
        check_declared(target)
        test = @test.nil? ? target.form == :name : @test
        Generators::Files.plan(target, desc: @desc, test:).write(force: @force, out: @stdout, cwd: Dir.pwd)
        target.declared? ? check_loaded(target) : @stdout.puts(usage_hint(target))
        EXIT_CODES[:ok]
      end

      def check_arguments(kind, argument, rest)
        raise UsageError, "no kind given (#{Generators::KIND_LIST})" unless kind
        raise UsageError, "unknown kind #{kind} (#{Generators::KIND_LIST})" unless Generators::KINDS.include?(kind)
        raise UsageError, "no name or path given" unless argument
        raise UsageError, "unexpected arguments: #{rest.join(" ")}" if rest.any?
      end

      # The project of the working directory, loaded once; its files that
      # did not load give the usual warnings.
      def project = @lookup.project(logger)

      def check_desc(target)
        return unless @desc
        raise UsageError, "--desc is for jobs, transforms and commands" unless target.declared?
        raise UsageError, "desc must be one line of text" if @desc.match?(/[\r\n]/)
      end

      # A name of the project declared in another file than the target's;
      # --force overwrites files, never names declared elsewhere.
      def check_declared(target)
        return unless target.form == :name && target.declared?

        other = project.declared(target.name).map(&:file).find { it != target.file }
        raise UsageError, "#{target.name} is already declared in #{project.relative(other)}" if other
      end

      # Loads the project at or above the new file again, without
      # warnings, and tells whether it has the new name. The files are
      # written either way.
      def check_loaded(target)
        file = Project.find(File.dirname(target.file))
        return unless file

        message = loaded_message(Project.load_file(file), target)
        @stderr.puts(message) if message
      rescue ProjectError => e
        @stderr.puts("warning: #{e.message.lines.first.chomp}; #{Generators.relative(target.file, Dir.pwd)} " \
                     "is not checked")
      end

      def loaded_message(project, target)
        error = project.load_errors.find { |path, _error| path == target.file }
        return "warning: #{project.load_error_summary(*error)}" if error
        return "warning: #{project.duplicate_message(target.name)}" if project.duplicates.key?(target.name)
        return if project.declared(target.name).any? { it.file == target.file }

        "note: #{Generators.relative(target.file, Dir.pwd)} is not loaded by the #{Project::FILE}; " \
          "it runs by path only"
      end

      def usage_hint(target) = "In a job: require_relative the file, then #{target.kind} #{target.constant}.new(...)"

    end
  end
end
