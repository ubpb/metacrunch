require_relative "../metacrunch"

class Metacrunch::File
  require_relative "./file/reader"
  require_relative "./file/writer"

  attr_accessor :content
  attr_accessor :entry_name # equals file_name for plain files
  attr_accessor :file_name

  def initialize(options = {})
    @content = options[:content]
    @entry_name = options[:entry_name]
    @file_name = options[:file_name]
  end

  def to_h
    {
      content: @content,
      entry_name: @entry_name,
      file_name: @file_name
    }
  end
end
