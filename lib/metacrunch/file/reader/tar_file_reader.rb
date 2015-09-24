require "rubygems/package"
require_relative "../reader"

class Metacrunch::File::Reader::TarFileReader
  include Enumerable

  def self.accepts?(filename)
    !!filename[/\.tar\Z|\.tar\.gz\Z|\.tgz\Z/]
  end

  def initialize(filename)
    @filename = filename
  end

  def each
    return enum_for(__method__) unless block_given?

    io =
    if @filename.end_with?("gz") # catches tgz and tar.gz
      Zlib::GzipReader.open(@filename)
    else
      File.open(@filename)
    end

    Gem::Package::TarReader.new(io).each do |_tar_entry|
      unless _tar_entry.directory?
        yield Metacrunch::File.new({
          content: _tar_entry.read,
          entry_name: _tar_entry.full_name,
          file_name: @filename
        })
      end
    end

    io.close
  end
end
