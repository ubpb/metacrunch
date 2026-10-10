# frozen_string_literal: true

# Sink for tests: keeps records, contexts and lifecycle events.
class CollectingSink

  attr_reader :records, :contexts, :events

  def initialize
    @records = []
    @contexts = []
    @events = []
  end

  def open(_context)
    @events << :open
  end

  def write(record, ctx)
    @records << record
    @contexts << ctx
  end

  def close
    @events << :close
  end

end
