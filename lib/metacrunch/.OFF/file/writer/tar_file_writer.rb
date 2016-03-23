require "rubygems/package"
require "zlib"
require_relative "../writer"

class Metacrunch::File::Writer::TarFileWriter
  def self.supports?(filename)
    !!filename[/\.tar\Z|\.tar\.gz\Z|\.tgz\Z/]
  end

  def initialize(filename)
    @io = File.open(filename, "w")
    @io = Zlib::GzipWriter.new(@io) if filename.end_with?("gz")
    @tar_writer = Gem::Package::TarWriter.new(@io)
  end

  def close
    @tar_writer.close
    @io.close
  end

  def write(options = {})
    @tar_writer.add_file_simple(options[:entry_name], 0644, options[:content].bytesize) do |_tar_entry|
      _tar_entry.write(options[:content])
    end
  end
end
