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
      io.flush if io
    end

    def close
      flush
      io.close if io
    end

  private

    def io
      @io ||= (@compressed == true) ? Zlib::GzipWriter.open(@path) : File.open(@path, "w")
    end

  end
end
