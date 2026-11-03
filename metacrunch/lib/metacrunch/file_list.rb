# frozen_string_literal: true

require "digest"
require "time"

module Metacrunch
  # A source of files: one record per file of directories, glob patterns
  # or single files, with the bytes as they are (nothing is unpacked).
  module FileList

    # MIME types by lowercase extension; others are application/octet-stream.
    TYPES = {
      "html" => "text/html", "htm" => "text/html", "xhtml" => "application/xhtml+xml", "pdf" => "application/pdf",
      "doc" => "application/msword",
      "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "xls" => "application/vnd.ms-excel",
      "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "ppt" => "application/vnd.ms-powerpoint",
      "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      "odt" => "application/vnd.oasis.opendocument.text", "ods" => "application/vnd.oasis.opendocument.spreadsheet",
      "odp" => "application/vnd.oasis.opendocument.presentation", "rtf" => "application/rtf", "txt" => "text/plain",
      "md" => "text/markdown", "markdown" => "text/markdown", "xml" => "application/xml",
      "json" => "application/json", "csv" => "text/csv", "epub" => "application/epub+zip", "eml" => "message/rfc822"
    }.freeze

    OCTET_STREAM = "application/octet-stream"

    module_function

    def type(path) = TYPES.fetch(File.extname(path).delete_prefix(".").downcase, OCTET_STREAM)

    # Source: yields {"id", "path", "size", "modified", "type", "sha256",
    # "content"} per file, sorted by path. id is the path relative to root:,
    # by default the deepest directory that holds the roots of all targets
    # (a directory itself, a file's directory, a pattern's fixed start), so
    # distinct files get distinct ids. A file that cannot be read, whose
    # name is not UTF-8 or that lies outside root: is yielded as
    # InvalidRecord, so the job's failure policy decides.
    class Reader

      GLOB = /[*?\[{]/
      private_constant :GLOB

      # targets: a directory (read recursively; hidden files only where a
      # pattern names them), a glob pattern or a file, or an Array of them;
      # Strings or Pathnames.
      def initialize(targets, root: nil)
        @targets = targets.is_a?(Array) ? targets : [targets]
        raise ArgumentError, "FileList::Reader needs at least one target" if @targets.empty?

        @targets.each do |target|
          next if path?(target)

          raise ArgumentError, "a target must be a String or a Pathname, got #{target.inspect}"
        end
        raise ArgumentError, "root must be a String or a Pathname, got #{root.inspect}" unless root.nil? || path?(root)

        @targets = @targets.map(&:to_s)
        @root = root && File.expand_path(root)
        @total = nil
        @done = 0
      end

      # Without a block an Enumerator.
      def each
        return enum_for(:each) unless block_given?

        files = @targets.flat_map { paths(it) }.select { File.file?(it) }.uniq.sort
        root = @root || common_root
        @total = files.size
        @done = 0
        files.each do |path|
          @done += 1
          yield record(path, root)
        end
      end

      # The share of the files yielded: 0.0 before the run, 1.0 at its end.
      def progress
        return 0.0 if @total.nil?

        @total.zero? ? 1.0 : @done.fdiv(@total)
      end

      private

      def path?(value) = value.is_a?(String) || value.is_a?(Pathname)

      def paths(target)
        return Dir.glob("**/*", base: target).map { File.expand_path(it, target) } if File.directory?(target)
        return [File.expand_path(target)] if File.file?(target)

        Dir.glob(target).map { File.expand_path(it) }
      end

      # A directory itself, a file's directory, a pattern's text up to the
      # last "/" before its first glob character.
      def own_root(target)
        return File.expand_path(target) if File.directory?(target)

        index = target.index(GLOB)
        return File.dirname(File.expand_path(target)) unless index

        fixed = target[0, index]
        File.expand_path(fixed.include?("/") ? fixed[0..fixed.rindex("/")] : ".")
      end

      def common_root
        parts = @targets.map { own_root(it).split("/") }
        common = parts.reduce { |shared, other| shared.take_while.with_index { |part, i| part == other[i] } }
        common.join("/").then { it.empty? ? "/" : it }
      end

      def record(path, root)
        return invalid(path, "the name is not valid UTF-8") unless path.valid_encoding?

        id = Pathname(path).relative_path_from(root).to_s
        return invalid(path, "outside root #{root}") if id == ".." || id.start_with?("../")

        content = File.binread(path)
        {"id" => id, "path" => path, "size" => content.bytesize, "modified" => File.mtime(path).utc.iso8601,
         "type" => FileList.type(path), "sha256" => Digest::SHA256.hexdigest(content), "content" => content}
      rescue SystemCallError => e
        InvalidRecord.new(raw: path, error: e)
      end

      def invalid(path, message) = InvalidRecord.new(raw: path, error: InputError.new(message))

    end

  end
end
