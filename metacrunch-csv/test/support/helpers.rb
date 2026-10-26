# frozen_string_literal: true

# Helpers shared by the tests.
module Helpers

  # A context as the engine passes it to a sink.
  def ctx(position = 1) = Metacrunch::Context.new(id: position, position:, logger: Logger.new(nil))

  # The records the reader yields for bytes.
  def read(bytes, **) = Metacrunch::Csv::Reader.new(StringIO.new(bytes.b), **).each.to_a

  # The bytes the writer writes for records.
  def written(records, **)
    io = StringIO.new("".b)
    writer = Metacrunch::Csv::Writer.new(io, **)
    writer.open(nil)
    records.each_with_index { |record, index| writer.write(record, ctx(index + 1)) }
    writer.close
    io.string
  end

  # The error the writer raises for records.
  def write_error(records, **) = assert_raises(Metacrunch::Error) { written(records, **) }

  # A tar archive of name => content.
  def tar(files)
    io = StringIO.new("".b)
    Gem::Package::TarWriter.new(io) do |tar|
      files.each { |name, content| tar.add_file_simple(name, 0o644, content.bytesize) { it.write(content) } }
    end
    io.string
  end

end
