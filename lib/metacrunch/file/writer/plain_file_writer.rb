require_relative "../writer"

class Metacrunch::File::Writer::PlainFileWriter
  def self.supports?(filename)
    true
  end

  def initialize(filename)
    @io = File.open(filename, "w")
  end

  def close
    @io.close
  end

  def write(options = {})
    @io.write(options[:content])
  end
end
