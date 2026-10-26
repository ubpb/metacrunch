# frozen_string_literal: true

require "metacrunch"
require "zip_kit"
require_relative "xlsx/version"
require_relative "xlsx/columns"
require_relative "xlsx/cells"
require_relative "xlsx/sheet"
require_relative "xlsx/package"
require_relative "xlsx/writer"

module Metacrunch
  # XLSX for metacrunch: a sink (Writer) that streams one worksheet.
  module Xlsx
  end
end
