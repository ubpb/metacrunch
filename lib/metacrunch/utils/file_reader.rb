module Metacrunch
  module Utils
    class FileReader

      def initialize
      end

      def read_files(files, &block)
        [*files].each do |filename|
          read_file(filename, &block)
        end
      end

      def read_file(filename, &block)
        if is_tar_file?(filename)
          read_tar_file(filename, &block)
        else
          read_regular_file(filename, &block)
        end
      end

    private

      def is_tar_file?(filename)
        filename.ends_with?(".tar") || filename.ends_with?(".tar.gz")
      end

      def is_gzip_file?(filename)
        filename.ends_with?(".gz")
      end

      def read_tar_file(filename, &block)
        io = is_gzip_file?(filename) ? Zlib::GzipReader.open(filename) : File.open(filename, "r")

        tarReader = Gem::Package::TarReader.new(io)
        tarReader.each do |entry|
          if entry.file?
            result = FileReaderResult.new(
              filename: entry.full_name,
              source_filename: filename,
              contents: entry.read,
              from_archive: true
            )

            yield(result)
          end
        end
      end

      def read_regular_file(filename, &block)
        if File.file?(filename)
          io = is_gzip_file?(filename) ? Zlib::GzipReader.open(filename) : File.open(filename, "r")

          result = FileReaderResult.new(
            filename: filename,
            source_filename: nil,
            contents: io.read
          )

          yield(result)
        end
      end

    end
  end
end
