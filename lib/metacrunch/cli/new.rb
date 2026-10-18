# frozen_string_literal: true

require "shellwords"

module Metacrunch
  class Cli
    # metacrunch new: creates a project (see Generators::Skeleton) in a
    # directory that is new, empty, or lacks the files of the skeleton.
    # Other files of the directory stay as they are.
    class NewCommand < Command

      NAME = "new"
      SUMMARY = "Create a project"
      USAGE = "new [--force] DIR"

      def initialize(streams, lookup)
        super
        @force = false
      end

      private

      def define_options(parser)
        parser.on("--force", "Overwrite existing files of the skeleton") { @force = true }
      end

      # Options may stand before or after DIR.
      def parse(parser, argv) = parser.permute!(argv)

      def execute(argv)
        dir = argv.shift
        check_dir(dir, argv)
        root = File.expand_path(dir)
        outer = Project.find(File.dirname(root))
        Generators::Skeleton.plan(root).write(force: @force, out: @stdout, cwd: Dir.pwd)
        if outer
          @stderr.puts("note: inside the project #{File.dirname(outer)}; below #{dir.chomp("/")}/ names resolve " \
                       "in the new project")
        end
        @stdout.puts(next_steps(dir, root))
        EXIT_CODES[:ok]
      end

      def check_dir(dir, rest)
        raise UsageError, "no directory given" unless dir
        raise UsageError, "unexpected arguments: #{rest.join(" ")}" if rest.any?
        if dir.end_with?(".rb")
          raise UsageError, "new creates a project; for a job file use metacrunch generate job #{dir}"
        end
        raise UsageError, "#{dir} is a file" if File.file?(dir)
      end

      def next_steps(dir, root)
        cd = root == Dir.pwd ? [] : ["cd #{Shellwords.escape(dir)}"]
        steps = [*cd, "bundle install", "bundle exec metacrunch generate job NAME", "bundle exec rake"]
        ["Next steps:", *steps.map { "  #{it}" }]
      end

    end
  end
end
