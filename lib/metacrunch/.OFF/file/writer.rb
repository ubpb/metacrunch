require_relative "../file"
require_relative "../processor"

class Metacrunch::File::Writer < Metacrunch::Processor
  require_relative "./writer/plain_file_writer"
  require_relative "./writer/tar_file_writer"
  require_relative "./writer/zip_file_writer"

  def initialize(filename)
    @writer =
    [TarFileWriter, ZipFileWriter, PlainFileWriter].find do |_writer|
      _writer.supports?(filename)
    end
    .try do |_appropriate_writer_class|
      _appropriate_writer_class.new(filename)
    end
  end

  def close
    @writer.close
  end

  def write(*args)
    @writer.write(*args)
  end
end
