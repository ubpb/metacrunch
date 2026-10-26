# frozen_string_literal: true

Metacrunch.job do
  source [1]
  map { raise SignalException, "TERM" }
end
