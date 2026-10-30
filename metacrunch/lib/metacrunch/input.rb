# frozen_string_literal: true

require "tempfile"

module Metacrunch
  # The documents of one or more targets, for sources and other readers:
  # gzip, tar and zip are detected by their content and unpacked, up to
  # MAX_LAYERS deep. Not a source itself: it has each_document, not each.
  # Used from one thread; only #progress may be read from another one. See
  # docs/files.md.
  class Input

    MAX_LAYERS = 4
    # The formats Input can unpack, as sources pass them to unpack:.
    UNPACK = [:gzip, :tar, :zip].freeze

    # A target that can be read at any offset, as a ZIP archive needs it:
    # io from start; position: see Zip.
    Seekable = Data.define(:io, :start, :position)
    private_constant :Seekable

    # targets: a path (String or Pathname), "-" for stdin, an IO (anything
    # with readpartial or read), or a non-empty Array of these. unpack: the
    # formats to unpack, of UNPACK; any other comes as a document with its
    # bytes. Checks types only and touches no file.
    def initialize(targets, unpack: [])
      list = targets.is_a?(Array) ? targets : [targets]
      raise ArgumentError, "targets must not be empty" if list.empty?

      @targets = list.map { target(it) }.freeze
      @unpack = unpack_formats(unpack)
      @total = nil
      @done = 0
    end

    # Yields a Stream and its name for every document. Checks all paths
    # before the first document. Without a block an Enumerator.
    def each_document(&)
      return enum_for(:each_document) unless block_given?

      @done = 0
      @total = total(check_paths)
      @targets.each { read_target(it, &) }
      @done = @total if @total
      nil
    end

    # The share of the files read so far, from 0.0 to 1.0 (compressed bytes
    # for gzip); nil before reading and unless all targets are regular
    # files.
    def progress
      total = @total
      return unless total
      return 1.0 if total.zero?

      [@done.fdiv(total), 1.0].min
    end

    private

    def target(target)
      return target.to_s if target.is_a?(Pathname)
      return target if target.is_a?(String) ? !target.empty? : io?(target)

      raise ArgumentError, "a target must be a path, \"-\" or an IO, got #{target.inspect}"
    end

    def io?(target) = target.respond_to?(:readpartial) || target.respond_to?(:read)

    def unpack_formats(unpack)
      return unpack.to_set.freeze if unpack.is_a?(Array) && unpack.all? { UNPACK.include?(it) }

      raise ArgumentError, "unpack must be an Array of :gzip, :tar and :zip, got #{unpack.inspect}"
    end

    # The File::Stat of every path; raises InputError for missing files,
    # directories and unreadable files.
    def check_paths
      @targets.filter_map do |target|
        next unless Files.path?(target)

        stat = File.stat(target)
        raise InputError, "#{target}: is a directory" if stat.directory?
        raise InputError, "#{target}: permission denied" unless File.readable?(target)

        stat
      rescue Errno::ENOENT
        raise InputError, "#{target}: no such file"
      rescue SystemCallError => e
        raise InputError, "#{target}: #{Files.reason(e)}"
      end
    end

    def total(stats)
      return unless stats.size == @targets.size && stats.all?(&:file?)

      stats.sum(&:size)
    end

    def read_target(target, &)
      return read_file(target, &) if Files.path?(target)

      io = target == STDIO ? $stdin : target
      name = Files.name(target)
      layers(Stream.new(Raw.new(io, name)), name, nil, 0, seekable(io), &)
    end

    # A Seekable for an IO that can seek and knows its size (a File, a
    # StringIO), from where it is; nil for pipes, sockets and stdin.
    def seekable(io)
      return unless [:seek, :pos, :size].all? { io.respond_to?(it) }

      Seekable.new(io:, start: io.pos, position: nil)
    rescue SystemCallError
      nil
    end

    # For progress, the file's share is the bytes read, or the offset a
    # ZIP archive was read up to, whichever is more, and its size at the
    # end.
    def read_file(path, &)
      file = open_file(path)
      begin
        before = @done
        count = ->(bytes) { @done += bytes } if @total
        position = ->(offset) { @done = [@done, before + offset].max } if @total
        seekable = Seekable.new(io: file, start: 0, position:) if file.stat.file?
        layers(Stream.new(Raw.new(file, path, count:)), path, path, 0, seekable, &)
        @done = before + file.size if @total
      ensure
        file.close
      end
    end

    def open_file(path)
      File.open(path, "rb")
    rescue Errno::ENOENT
      raise InputError, "#{path}: no such file"
    rescue SystemCallError => e
      raise InputError, "#{path}: #{Files.reason(e)}"
    end

    # Yields the documents of stream. file: the path, for the hint of an
    # unsupported format on the outer layer of a file, else nil; depth: the
    # layers of gzip, tar and zip around stream; seekable: the target of
    # an outer layer, if it can seek.
    def layers(stream, name, file, depth, seekable = nil, &)
      format = detect(stream)
      format = :plain if UNPACK.include?(format) && !@unpack.include?(format)
      case format
      when :plain then document(stream, name, &)
      when :gzip then gzip(stream, name, depth, &)
      when :tar then tar(stream, name, depth, &)
      when :zip then zip(stream, name, file, depth, seekable, &)
      else raise InputError, format.message(name, file)
      end
    end

    # Reads ahead block by block until the first bytes tell the format.
    def detect(stream)
      loop do
        head, complete = stream.lookahead(Formats::PEEK)
        format = Formats.detect(head, complete:)
        return format if format
      end
    end

    def document(stream, name)
      yield stream, name
    ensure
      stream.close
    end

    def gzip(stream, name, depth, &)
      deeper(name, depth)
      gzip = Gzip.new(stream, name)
      begin
        layers(Stream.new(gzip), name, nil, depth + 1, &)
      ensure
        gzip.finish
      end
    end

    def tar(stream, name, depth, &)
      deeper(name, depth)
      Tar.new(stream, name).each_member do |member, member_name|
        layers(member, member_name, nil, depth + 1, &)
      end
    end

    # A ZIP archive's directory is at its end: a Seekable target is read
    # directly, anything else is copied into a temporary file first, which
    # is removed afterwards, also on errors and interrupts.
    def zip(stream, name, file, depth, seekable, &)
      deeper(name, depth)
      if seekable
        archive = Zip.new(seekable.io, name, start: seekable.start, position: seekable.position)
        return zip_documents(archive, name, file, depth, &)
      end

      copy = temporary_file(name)
      begin
        spool(stream, copy, name)
        zip_documents(Zip.new(copy, name), name, file, depth, &)
      ensure
        copy.close
      end
    end

    # Anonymous: the file has no name in the directory, so closing it, or
    # the end of the process however it ends, frees its space. Errors in
    # creating it are named; errors of the block that reads the documents
    # are not, so only the creation is rescued.
    def temporary_file(name)
      Tempfile.create("metacrunch-zip", anonymous: true).binmode
    rescue SystemCallError => e
      raise copy_error(name, e)
    rescue ArgumentError => e # no temporary directory to write to
      raise InputError, "#{name}: #{e.message}"
    end

    # Errors in reading stream are InputErrors already (Raw); a system
    # error here is one of the copy.
    def spool(stream, copy, name)
      IO.copy_stream(stream, copy)
      copy.flush
    rescue SystemCallError => e
      raise copy_error(name, e)
    end

    # Names the copy and where it is, so a full disk points to TMPDIR.
    def copy_error(name, error)
      InputError.new("#{name}: #{Files.reason(error)} for a temporary copy in #{Dir.tmpdir} (TMPDIR)")
    end

    # Refuses unsupported entries before the first document. A document
    # read only in part is read to its end afterwards, to check it, as a
    # tar member is.
    def zip_documents(zip, name, file, depth, &)
      ZipCheck.check(zip, name, file)
      zip.entries.each do |entry|
        next unless entry.document?

        member = zip.member(entry)
        layers(Stream.new(member), "#{name}:#{entry.name}", nil, depth + 1, &)
        member.drain
      end
    end

    def deeper(name, depth)
      raise InputError, "#{name}: more than #{MAX_LAYERS} layers of gzip, tar and zip" if depth == MAX_LAYERS
    end

  end
end

require_relative "input/stream"
require_relative "input/raw"
require_relative "input/formats"
require_relative "input/gzip"
require_relative "input/tar"
require_relative "input/zip"
require_relative "input/zip_check"
