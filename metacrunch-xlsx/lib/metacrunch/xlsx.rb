# frozen_string_literal: true

require "zlib"
require "metacrunch"
require "zip_kit"
require_relative "xlsx/version"
require_relative "xlsx/columns"
require_relative "xlsx/entry"
require_relative "xlsx/cells"
require_relative "xlsx/sheet"
require_relative "xlsx/package"
require_relative "xlsx/writer"

module Metacrunch
  # XLSX for metacrunch: a sink (Writer) that streams one worksheet.
  module Xlsx

    # Runs the block with interrupts (Ctrl-C) held back until it returns: an
    # interrupt inside zip_kit, between deflating data and adding it to the
    # CRC, would leave a ZIP entry that Excel has to repair.
    def self.uninterrupted(&) = Thread.handle_interrupt(Object => :never, &)

  end
end
