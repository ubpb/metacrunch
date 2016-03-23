require "rubygems/package"
require_relative "./file_reader_entry"

module Metacrunch
  class FileReader

    def initialize(filenames)
      @filenames = [*filenames].map{|f| f.presence}.compact
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      @filenames.each do |_filename|
        if is_archive?(_filename)
          read_archive(_filename, &block)
        else
          read_regular_file(_filename, &block)
        end
      end
    end

  private

    def is_archive?(filename)
      filename.ends_with?(".tar") || filename.ends_with?(".tar.gz")
    end

    def is_gzip_file?(filename)
      filename.ends_with?(".gz")
    end

    def read_regular_file(filename, &block)
      if ::File.file?(filename)
        io = is_gzip_file?(filename) ? Zlib::GzipReader.open(filename) : ::File.open(filename, "r")
        yield Entry.new(filename: filename, archive_filename: nil, contents: io.read)
      end
    end

    def read_archive(filename, &block)
      io        = is_gzip_file?(filename) ? Zlib::GzipReader.open(filename) : ::File.open(filename, "r")
      tarReader = Gem::Package::TarReader.new(io)

      tarReader.each do |_tar_entry|
        if _tar_entry.file?
          yield Entry.new(
            filename: filename,
            archive_filename: _tar_entry.full_name,
            contents: _tar_entry.read
          )
        end
      end
    end

  end
end
