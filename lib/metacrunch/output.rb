# frozen_string_literal: true

require "zlib"

module Metacrunch
  # Where a sink writes: a file (gzip if its name ends with .gz), stdout
  # ("-") or an IO. A closed pipe ends the run as SIGPIPE; own files are
  # closed, IOs from outside only flushed. Used from one thread. See
  # docs/files.md.
  class Output

    GZIP = ".gz"
    ARCHIVES = [".tar", ".tar.gz", ".tgz"].freeze
    # Endings of names whose content metacrunch cannot write: the format,
    # and the command that would write it from plain output.
    COMPRESSORS = {
      ".bz2" => ["bzip2", "bzip2 > PATH"], ".xz" => ["xz", "xz > PATH"], ".zst" => ["zstd", "zstd > PATH"],
      ".zip" => ["zip", "zip -q PATH -"]
    }.freeze

    # target: a path (String or Pathname), "-" for stdout or an IO (anything
    # with write). Checks the type only and touches no file.
    def initialize(target)
      @target = target.is_a?(Pathname) ? target.to_s : target
      unless @target.is_a?(String) ? !@target.empty? : @target.respond_to?(:write)
        raise ArgumentError, "a target must be a path, \"-\" or an IO, got #{target.inspect}"
      end

      @name = Files.name(@target)
      @io = nil
      @file = nil
      @broken = false
    end

    # Creates or truncates a file; "-" is the $stdout of this moment.
    def open
      raise OutputError, "#{@name}: already open" if @io

      @io = output
      self
    end

    # Raises SignalException("PIPE") once when the reader of a pipe went
    # away; afterwards it writes nothing.
    def write(string)
      raise IOError, "#{@name}: not open" unless @io

      guard { @io.write(string) }
      nil
    end

    # Closes an own file, flushes an IO from outside. Does nothing before
    # open and the second time.
    def close
      io = @io
      file = @file
      @io = nil
      @file = nil
      return unless io
      return discard(io, file) if @broken

      guard { file ? io.close : flush(io) }
    ensure
      discard(io, file) if file && !file.closed?
    end

    private

    def output
      return $stdout if @target == STDIO
      return @target unless @target.is_a?(String)

      refuse
      @file = File.open(@target, "wb")
      @target.downcase.end_with?(GZIP) ? Zlib::GzipWriter.new(@file) : @file
    rescue Errno::ENOENT
      raise OutputError, "#{@name}: no such directory"
    rescue SystemCallError => e
      raise OutputError, "#{@name}: #{Files.reason(e)}"
    end

    def refuse
      name = @target.downcase
      raise OutputError, "#{@name}: metacrunch cannot write tar archives" if name.end_with?(*ARCHIVES)

      _, (format, command) = COMPRESSORS.find { |ending, _| name.end_with?(ending) }
      return unless format

      raise OutputError, "#{@name}: metacrunch cannot write #{format}; write plain output and compress it, " \
                         "e.g. metacrunch run job.rb | #{command.sub("PATH", @target)}"
    end

    def flush(io)
      io.flush if io.respond_to?(:flush)
    end

    def guard
      return if @broken

      yield
    rescue Errno::EPIPE
      @broken = true
      raise SignalException, "PIPE"
    rescue SystemCallError => e
      raise OutputError, "#{@name}: #{Files.reason(e)}"
    end

    # Closes an own file whose buffer can no longer be written.
    def discard(io, file)
      return unless file

      begin
        io.close unless io.closed?
      rescue Errno::EPIPE, IOError, Zlib::Error
        nil
      end
      file.close unless file.closed?
    end

  end
end
