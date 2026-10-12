# frozen_string_literal: true

require "metacrunch"
require "rubygems/package"
require "zlib"

module Metacrunch
  module Marcxml
    # A metacrunch source: reads MARCXML from files (.xml, .gz, .tar,
    # .tar.gz, .tgz), stdin ("-") or IOs and yields a Record per record, or
    # with parse: false its XML string, which is cheaper to send to workers.
    # A record that cannot be parsed is yielded as Metacrunch::InvalidRecord.
    class Reader

      STDIO = "-"

      # How often (in records) the position in a file is sampled for
      # #progress.
      PROGRESS_EVERY = 256

      GZIP_MAGIC = "\x1F\x8B".b
      BOM = "\xEF\xBB\xBF".b

      # targets: a path (String or Pathname), "-" for stdin, an IO, or an
      # Array of those. IOs are never closed.
      def initialize(targets, parse: true, normalize: nil)
        @targets = targets.is_a?(Array) ? targets : [targets]
        raise ArgumentError, "targets must not be empty" if @targets.empty?

        @targets.each { check_target(it) }
        Marcxml.check_normalize(normalize)
        if normalize && !parse
          raise ArgumentError, "normalize: needs parse: true; with parse: false normalize in the step that parses: " \
                               "Marcxml.parse(xml, normalize: :nfc)"
        end
        @parse = parse
        @normalize = normalize
        @total = nil
        @done = 0
      end

      # Without a block an Enumerator.
      def each
        return enum_for(:each) unless block_given?

        @total = total_size
        @done = 0
        finished = 0
        @targets.each do |target|
          with_input(target) do |input, file|
            count = 0
            each_document(input, target, file) do |document|
              Marcxml.each_xml(document) do |xml|
                count += 1
                @done = finished + file.pos if file && (count % PROGRESS_EVERY).zero?
                yield(@parse ? record(xml) : xml)
              end
            end
            finished += file.size if file
            @done = finished
          end
        end
      end

      # The share of the files read so far, from 0.0 to 1.0 (the compressed
      # position for gzip files); nil before reading and when a target is
      # stdin, an IO or not a regular file.
      def progress
        total = @total
        return unless total
        return 1.0 if total.zero?

        [@done.fdiv(total), 1.0].min
      end

      private

      def check_target(target)
        return if path?(target) || target == STDIO || target.respond_to?(:readpartial) || target.respond_to?(:read)

        raise ArgumentError, "a target must be a path, \"-\" or an IO, got #{target.inspect}"
      end

      def path?(target) = (target.is_a?(String) && target != STDIO) || target.is_a?(Pathname)

      # The size of all targets if all are regular files, else nil.
      def total_size
        @targets.sum do |target|
          return nil unless path?(target) && File.file?(target.to_s)

          File.size(target.to_s)
        end
      end

      # Yields the IO to read and the File for progress (nil for stdin,
      # IOs and files that are not regular). Files are closed in any case.
      def with_input(target)
        return yield($stdin, nil) if target == STDIO
        return yield(target, nil) unless path?(target)

        File.open(target.to_s, "rb") do |file|
          yield file, (file.stat.file? ? file : nil)
        end
      end

      # Yields each MARCXML document of input: input itself, its gzip
      # content, or each regular file of a tar archive. A regular file that
      # starts like gzip is read as gzip whatever its name; one that does
      # not start like XML raises.
      def each_document(input, target, file, &)
        name = path?(target) ? target.to_s : ""
        if name.end_with?(".tar.gz", ".tgz")
          gunzip(input) { each_entry(it, &) }
        elsif name.end_with?(".tar")
          each_entry(input, &)
        elsif name.end_with?(".gz") || head(file, 2) == GZIP_MAGIC
          members(input, &)
        else
          check_xml(file, name) if file
          yield input
        end
      end

      # The first bytes of a regular file, which stays at its start.
      def head(file, length)
        return unless file

        bytes = file.read(length).to_s
        file.rewind
        bytes
      end

      def check_xml(file, name)
        text = head(file, 64).delete_prefix(BOM).lstrip
        return if text.empty? || text.start_with?("<")

        raise Metacrunch::Error, "#{name} is not XML: it starts with #{text[0, 16].inspect}"
      end

      def gunzip(io)
        gzip = Zlib::GzipReader.new(io)
        yield gzip
      ensure
        gzip&.finish
      end

      def members(io)
        gzip = GzipMembers.new(io)
        yield gzip
      ensure
        gzip&.finish
      end

      def each_entry(io)
        Gem::Package::TarReader.new(io).each { |entry| yield entry if entry.file? }
      end

      # The content of all members of a gzip stream, as zcat reads it: files
      # written with `cat a.gz b.gz` or `gzip >>` have several. Data after
      # the last member that is not gzip raises Zlib::GzipFile::Error.
      class GzipMembers

        def initialize(io)
          @io = io
          @gzip = Zlib::GzipReader.new(io)
        end

        def read(length)
          loop do
            chunk = @gzip.read(length)
            return chunk unless chunk.nil? || chunk.empty?
            return unless next_member?
          end
        end

        def finish
          @gzip.finish unless @gzip.closed?
        end

        private

        def next_member?
          unused = @gzip.unused
          @gzip.finish
          @io.ungetbyte(unused) if unused
          return false if @io.eof?

          @gzip = Zlib::GzipReader.new(@io)
          true
        end

      end
      private_constant :GzipMembers

      def record(xml)
        Marcxml.parse(xml, normalize: @normalize)
      rescue ParseError => e
        Metacrunch::InvalidRecord.new(raw: xml, error: e)
      end

    end
  end
end
