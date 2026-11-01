# frozen_string_literal: true

module Metacrunch
  module Xlsx

    # The error of an InvalidRecord: a row that does not fit the header, or
    # a cell whose value cannot be read.
    class ParseError < Metacrunch::Error; end

    # An InputError for a workbook whose structure is broken; part: the
    # part of the archive, e.g. "xl/worksheets/sheet1.xml".
    def self.broken(name, part, reason) = InputError.new("#{name}: broken XLSX workbook (#{part}: #{reason})")

  end
end
