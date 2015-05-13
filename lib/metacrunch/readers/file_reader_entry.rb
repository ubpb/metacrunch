require_relative "./file_reader"

module Metacrunch
  module Readers
    class FileReader
      class Entry

        attr_reader :filename, :archive_filename, :contents

        def initialize(filename:, archive_filename:nil, contents:nil)
          @filename         = filename
          @archive_filename = archive_filename.presence
          @contents         = contents
        end

        def from_archive?
          @archive_filename != nil
        end

      end
    end
  end
end
