# frozen_string_literal: true

module Metacrunch
  # The documents of one or more targets, for sources and other readers:
  # gzip and tar are detected by their content and unpacked, up to
  # MAX_LAYERS deep. Not a source itself: it has each_document, not each.
  # Used from one thread; only #progress may be read from another one. See
  # docs/files.md.
  class Input

    MAX_LAYERS = 4

    # targets: a path (String or Pathname), "-" for stdin, an IO (anything
    # with readpartial or read), or a non-empty Array of these. Checks types
    # only and touches no file.
    def initialize(targets)
      list = targets.is_a?(Array) ? targets : [targets]
      raise ArgumentError, "targets must not be empty" if list.empty?

      @targets = list.map { target(it) }.freeze
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
      layers(Stream.new(Raw.new(io, name)), name, nil, 0, &)
    end

    def read_file(path, &)
      file = open_file(path)
      begin
        count = ->(bytes) { @done += bytes } if @total
        layers(Stream.new(Raw.new(file, path, count:)), path, path, 0, &)
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

    # Yields the documents of stream. file: what the hint of an unsupported
    # format names (the path, a member's name, or nil); depth: the layers
    # of gzip and tar around stream.
    def layers(stream, name, file, depth, &)
      format = detect(stream)
      case format
      when :plain then document(stream, name, &)
      when :gzip then gzip(stream, name, file, depth, &)
      when :tar then tar(stream, name, depth, &)
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

    def gzip(stream, name, file, depth, &)
      deeper(name, depth)
      gzip = Gzip.new(stream, name)
      begin
        layers(Stream.new(gzip), name, file, depth + 1, &)
      ensure
        gzip.finish
      end
    end

    def tar(stream, name, depth, &)
      deeper(name, depth)
      Tar.new(stream, name).each_member do |member, member_name, full_name|
        layers(member, member_name, full_name, depth + 1, &)
      end
    end

    def deeper(name, depth)
      raise InputError, "#{name}: more than #{MAX_LAYERS} layers of gzip and tar" if depth == MAX_LAYERS
    end

  end
end

require_relative "input/stream"
require_relative "input/raw"
require_relative "input/formats"
require_relative "input/gzip"
require_relative "input/tar"
