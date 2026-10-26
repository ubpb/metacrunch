# frozen_string_literal: true

# Sink for tests: keeps records and contexts like CollectingSink, but reports
# the records listed in bad as not written (Metacrunch::SinkFailures), from
# write and, with batch:, from write_batch.
class FailingSink < CollectingSink

  def initialize(*bad)
    super()
    @bad = bad
  end

  def write(record, ctx) = write_batch([record], [ctx])

  def write_batch(records, contexts)
    failed = {}
    records.zip(contexts).each_with_index do |(record, ctx), index|
      next failed[index] = ArgumentError.new("bad #{record}") if @bad.include?(record)

      @records << record
      @contexts << ctx
    end
    raise Metacrunch::SinkFailures, failed unless failed.empty?
  end

end
