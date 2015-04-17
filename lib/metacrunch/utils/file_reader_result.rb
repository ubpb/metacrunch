module Metacrunch
  module Utils
    class FileReaderResult

      attr_reader :filename, :source_filename, :contents

      def initialize(filename:, source_filename:nil, contents:nil, from_archive:false)
        @filename        = filename
        @source_filename = source_filename
        @contents        = contents
        @from_archive    = from_archive
      end

      def from_archive?
        @from_archive
      end

    end
  end
end
