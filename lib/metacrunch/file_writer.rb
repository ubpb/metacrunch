module Metacrunch
  class FileWriter

    class FileExistError < RuntimeError ; end


    def initialize(filename, override: false, compress: nil)
      @path       = File.expand_path(filename)
      @compressed = (compress ||= @path.ends_with?(".gz"))

      if File.exist?(@path) && !override
        raise FileExistError, "File #{@path} already exists. Set override = true to override the existing file."
      end
    end

    def write(data, options = {})
      if block_given?
        yield(io)
      else
        io.write(data)
      end
    end

    def flush
      file_io.flush if file_io
      gzip_io.flush if gzip_io
    end

    def close
      flush
      file_io.close if file_io
      gzip_io.close if gzip_io
    end

  private

    def io
      @io ||= (@compressed == true) ? gzip_io : file_io
    end

    def file_io
      @file_io ||= File.open(@path, "w")
    end

    def gzip_io
      @gzip_io ||= Zlib::GzipWriter.open(@path)
    end

  end
end
