require "zip"
require_relative "../writer"

class Metacrunch::File::Writer::ZipFileWriter
  def self.supports?(filename)
    !!filename[/\.zip\Z/]
  end

  def self.write(*args)
  end

=begin
  def each
    return enum_for(__method__) unless block_given?

    Zip::File.open(@filename) do |_zip_file|
      _zip_file.each do |_zip_entry|
        unless _zip_entry.directory?
          yield Metacrunch::File.new({
            content: _zip_entry.get_input_stream.read,
            entry_name: _zip_entry.name,
            file_name: @filename
          })
        end
      end
    end
  end
=end
end
