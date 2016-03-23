require_relative "../file"
require_relative "../processor"

class Metacrunch::File::Reader < Metacrunch::Processor
  require_relative "./reader/file_system_fetcher"
  require_relative "./reader/plain_file_reader"
  require_relative "./reader/scp_fetcher"
  require_relative "./reader/tar_file_reader"
  require_relative "./reader/zip_file_reader"

  include Enumerable

  def initialize(options = {})
    @bulk_size = options[:bulk_size].try(:to_i) || 1
    @urls = [
      options[:filename], options[:filenames],
      options[:url], options[:urls]
    ]
    .flatten
    .compact
    .map do |_filename_or_url|
      if (_url = _filename_or_url)[/\A\w+:\/\//]
        _url
      else
        Dir.glob(File.expand_path(_filename_or_url)).map do |_filename|
          "file://#{_filename}"
        end
      end
    end
    .flatten # because there might be arrays again because of Dir.glob

    @force_content_encoding = options[:force_content_encoding]
    @password = options[:password]
    @username = options[:username]
  end

  def call(items = [], pipeline = nil)
    @chunks_of_entries_enumerator ||= each_slice(@bulk_size) # instance method from Enumerable
   
    begin
      items.concat(@chunks_of_entries_enumerator.next)
    rescue StopIteration
      pipeline.try(:terminate!)
    end
  end

  def each
    return enum_for(__method__) unless block_given?

    @urls.each do |_url|
      [FileSystemFetcher, ScpFetcher].find do |_fetcher|
        _fetcher.accepts?(_url)
      end
      .try do |_appropriate_fetcher|
        _appropriate_fetcher.new(_url, username: @username, password: @password).each do |_filename|
          [TarFileReader, ZipFileReader, PlainFileReader].find do |_reader| # PlainFileReader as last will read any file
            _reader.accepts?(_filename)
          end
          .try do |_appropriate_reader|
            _appropriate_reader.new(_filename).each do |_file|
              if @force_content_encoding.present?
                _file.content.try(:force_encoding, @force_content_encoding)
              end

              yield _file
            end
          end
        end
      end
    end
  end
end
