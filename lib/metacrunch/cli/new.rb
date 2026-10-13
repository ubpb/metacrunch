# frozen_string_literal: true

require "fileutils"

module Metacrunch
  class Cli
    # metacrunch new: creates a filter job (JSON Lines from stdin to stdout)
    # that runs right away, and with --test a Minitest test for it.
    class NewCommand < Command

      NAME = "new"
      SUMMARY = "Create a job file"
      USAGE = "new [--test] [--force] PATH"

      def initialize(streams)
        super
        @test = false
        @force = false
      end

      private

      def define_options(parser)
        parser.on("--test", "Also create test/NAME_test.rb") { @test = true }
        parser.on("--force", "Overwrite existing files") { @force = true }
      end

      def execute(argv)
        path = argv.shift
        raise UsageError, "no path given" unless path
        raise UsageError, "unexpected arguments: #{argv.join(" ")}" if argv.any?
        raise UsageError, "#{path} is a directory; give a file name" if path.end_with?("/")

        path = "#{path}.rb" unless path.end_with?(".rb")
        name = File.basename(path, ".rb")
        unless Names.valid?(name)
          raise UsageError, "#{File.basename(path)}: #{name.inspect} is not a valid job name; use a-z, 0-9, _ and -"
        end

        write(files(path, name))
        File.chmod(0o755, path)
        EXIT_CODES[:ok]
      end

      # {path => content} of the files to create. Raises UsageError if one
      # exists and --force is not given.
      def files(path, name)
        templates = {path => job_template(name, path)}
        templates[File.join("test", "#{name}_test.rb")] = test_template(name, path) if @test
        existing = templates.keys.select { File.exist?(it) }
        raise UsageError, "#{existing.join(", ")} already exists; use --force to overwrite" if existing.any? && !@force

        templates
      end

      def write(files)
        files.each do |file, content|
          FileUtils.mkdir_p(File.dirname(file))
          File.write(file, content)
          @stdout.puts("created #{file}")
        end
      end

      def job_template(name, path)
        <<~RUBY
          #!/usr/bin/env metacrunch
          # frozen_string_literal: true

          # Reads JSON Lines from stdin, writes JSON Lines to stdout:
          #   metacrunch run #{path} < in.jsonl > out.jsonl
          # Declare a source or sink to read or write elsewhere.
          Metacrunch.job #{name.inspect} do
            params do
              # param :index, String, required: true, desc: "Elasticsearch index"
            end

            # source MySource.new(params.files), id: ->(record) { record["id"] }

            reject("No id") { it["id"].nil? }
            map do |record, ctx|
              ctx.mark("No title") unless record.key?("title")
              record
            end

            # sink MySink.new, batch: 1000
          end
        RUBY
      end

      def test_template(name, path)
        job = Pathname(path).expand_path.relative_path_from(Pathname("test").expand_path)
        <<~RUBY
          # frozen_string_literal: true

          require "minitest/autorun"
          require "metacrunch"
          require "metacrunch/testing"

          class #{class_name(name)}Test < Minitest::Test

            JOB = File.expand_path(#{job.to_s.inspect}, __dir__)

            def test_keeps_records_with_an_id
              result = Metacrunch::Testing.run(Metacrunch.load_job(JOB), source: [{"id" => 1}, {"title" => "x"}])

              assert_equal [{"id" => 1}], result.records
            end

          end
        RUBY
      end

      def class_name(name)
        camel = name.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
        camel.match?(/\A[A-Z]/) ? camel : "Job#{camel}"
      end

    end
  end
end
