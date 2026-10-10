# frozen_string_literal: true

require_relative "../metacrunch"

module Metacrunch
  # Runs jobs in tests without I/O: all sinks are replaced by in-memory
  # sinks, and the source can be replaced by any Enumerable.
  module Testing

    # Keeps records and their contexts.
    class MemorySink

      attr_reader :records, :contexts

      def initialize
        @records = []
        @contexts = []
      end

      def write(record, ctx)
        @records << record
        @contexts << ctx
      end

    end

    # records: what reached the sink. rejects: [record, Rejection] pairs.
    # errors: [record, Failure] pairs.
    Result = Data.define(:records, :rejects, :errors, :stats, :status, :error)

    module_function

    # params are bound like CLI values (strings are converted), without
    # environment lookup. The job's sinks are built but never opened.
    def run(job, params: {}, source: nil, logger: Logger.new(nil))
      unless source.nil? || source.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{source.inspect}"
      end

      pipeline = job.pipeline(binder: ->(schema) { schema.bind_hash(params) }, logger:)
      memory = {sink: MemorySink.new, rejects: MemorySink.new, errors: MemorySink.new}
      pipeline = pipeline.with(source: source || pipeline.source,
                               **memory.transform_values { |sink| SinkAdapter.new(sink) })
      result = Engine.new(pipeline).run
      Result.new(
        records: memory[:sink].records,
        rejects: memory[:rejects].records.zip(memory[:rejects].contexts.map(&:rejection)),
        errors: memory[:errors].records.zip(memory[:errors].contexts.map(&:failure)),
        stats: result.stats,
        status: result.status,
        error: result.error
      )
    end

  end
end
