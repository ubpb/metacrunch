# frozen_string_literal: true

module Metacrunch
  module Generators
    # The files of one `new` or `generate`: all are written, or none if one
    # exists already and force is not given.
    class Plan

      Entry = Data.define(:path, :content, :executable)

      attr_reader :entries

      def initialize
        @entries = []
      end

      # path: absolute. executable: mode 0755 instead of the default.
      def add(path, content, executable: false)
        @entries << Entry.new(path: path.to_s, content:, executable:)
        self
      end

      # Writes the files, creating their directories, and puts
      # "created PATH" on out for each, PATH relative to cwd. Raises
      # UsageError before writing anything if a file exists and force is
      # false.
      def write(force:, out:, cwd:)
        existing = @entries.map(&:path).select { File.exist?(it) }.map { Generators.relative(it, cwd) }
        if existing.any? && !force
          raise UsageError, "#{existing.join(", ")} already #{existing.one? ? "exists" : "exist"}; " \
                            "use --force to overwrite"
        end

        @entries.each { write_entry(it, out, cwd) }
        nil
      end

      private

      def write_entry(entry, out, cwd)
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.content)
        File.chmod(0o755, entry.path) if entry.executable
        out.puts("created #{Generators.relative(entry.path, cwd)}")
      end

    end
  end
end
