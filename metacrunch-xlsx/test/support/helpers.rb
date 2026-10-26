# frozen_string_literal: true

# Helpers shared by the tests. They expect @dir, a temporary directory.
module Helpers

  # A context as the engine passes it to a sink.
  def ctx(position = 1) = Metacrunch::Context.new(id: position, position:, logger: Logger.new(nil))

  # Writes records to a file in @dir and returns its path.
  def xlsx(records, name: "out.xlsx", **)
    path = File.join(@dir, name)
    writer = Metacrunch::Xlsx::Writer.new(path, **)
    writer.open(nil)
    records.each_with_index { |record, index| writer.write(record, ctx(index + 1)) }
    writer.close
    path
  end

  # The error the writer raises for records.
  def write_error(records, **) = assert_raises(Metacrunch::Error) { xlsx(records, name: "error.xlsx", **) }

  # The rows of the worksheet as roo reads them; [] for an empty sheet.
  def rows(path)
    sheet = Roo::Excelx.new(path).sheet(0)
    sheet.first_row ? sheet.to_a : []
  end

  # name => content of the parts, in the order of the ZIP container.
  def parts(path)
    Zip::File.open(path) { |zip| zip.entries.to_h { [it.name, it.get_input_stream.read] } }
  end

  # The XML of the worksheet.
  def sheet_xml(path) = parts(path).fetch("xl/worksheets/sheet1.xml")

  # Replaces a constant of Metacrunch::Xlsx::Sheet while the block runs.
  def with_limit(name, value)
    sheet = Metacrunch::Xlsx::Sheet
    original = sheet.const_get(name)
    sheet.send(:remove_const, name)
    sheet.const_set(name, value)
    yield
  ensure
    sheet.send(:remove_const, name)
    sheet.const_set(name, original)
  end

  # Runs the block in a thread, raises Interrupt in it while gate holds it,
  # then lets it go on; the thread must end with that Interrupt.
  def interrupted(gate, &)
    thread = Thread.new(&)
    thread.report_on_exception = false
    unless gate.held?
      thread.join(1) # raises what the thread ended with, if it ended

      flunk("the thread did not reach the gate")
    end
    thread.raise(Interrupt)
    gate.open
    assert_raises(Interrupt) { thread.join }
  end

end
