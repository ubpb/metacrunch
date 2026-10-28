# frozen_string_literal: true

module Metacrunch

  # Yielded by a source instead of a record to have the records it yielded
  # so far written now: the workers get their partial batch, and the sinks
  # write what they buffer for batch:. It is no record. A source that waits
  # for data yields it when it waits, not after every record, since each
  # one costs the sinks a partial batch.
  FLUSH = Object.new
  def FLUSH.inspect = "Metacrunch::FLUSH"
  FLUSH.freeze

end
