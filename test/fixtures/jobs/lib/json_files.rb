# frozen_string_literal: true

require "json"

# Source: reads a JSON file that contains an array of records.
class JsonArrayFile

  def initialize(path)
    @path = path
  end

  def each(&)
    JSON.parse(File.read(@path)).each(&)
  end

end

# Sink: writes one JSON document per line.
class JsonLinesFile

  def initialize(path)
    @path = path
  end

  def open(_context)
    @file = File.open(@path, "w")
  end

  def write_batch(records)
    records.each { |record| @file.puts(JSON.generate(record)) }
  end

  def write(record)
    write_batch([record])
  end

  def close
    @file&.close
  end

end
