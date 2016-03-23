require_relative "../reader"

class Metacrunch::File::Reader::PlainFileReader
  include Enumerable

  def self.accepts?(filename)
    true
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

    yield Metacrunch::File.new({
      content: io.read,
      entry_name: File.basename(@filename),
      file_name: @filename,
      is_directory: false
    })

    io.close
  end
end
