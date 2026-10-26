# frozen_string_literal: true

require_relative "lib/printing_sink"

# Prints two records, then is interrupted.
Metacrunch.job do
  source [1, 2, 3]
  map { it == 3 ? raise(Interrupt) : it }
  sink PrintingSink.new
end
