require "rubygems/package"

module Metacrunch
  class TarWriter < FileWriter

    def write(data, options = {})
      raise ArgumentError, "Missing option 'filename'" if options[:filename].blank?

      io.add_file_simple(options[:filename], 0644, data.bytesize) do |_io|
        if block_given?
          yield(_io)
        else
          _io.write(data)
        end
      end
    end

  private

    def io
      @io ||=  Gem::Package::TarWriter.new(super)
    end

  end
end
