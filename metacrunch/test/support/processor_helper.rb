# frozen_string_literal: true

# Builds a Processor from a recipe and notes what leaves its chain.
module ProcessorHelper

  include PipelineHelper

  # Notes what leaves the chain; errors: the errors of failed records,
  # contexts: the contexts of delivered ones.
  class RecordingOutlet

    attr_reader :events, :errors, :contexts

    def initialize
      @events = []
      @errors = []
      @contexts = []
    end

    def deliver(record, ctx)
      @contexts << ctx
      @events << [:deliver, record, ctx.position]
    end

    def reject(record, ctx) = @events << [:reject, record, ctx.rejection.reason]

    def fail(record, ctx)
      @errors << ctx.failure.error
      @events << [:fail, record, ctx.failure.step]
    end

  end

  # The stats of the last processor built.
  attr_reader :processor_stats

  def build_processor(outlet, stats: nil, observer: nil, &)
    pipeline = build_pipeline(&)
    stats ||= Metacrunch::StatsCollector.new(pipeline.steps.map(&:name), profile: pipeline.profile)
    @processor_stats = stats
    Metacrunch::Processor.new(pipeline, stats:, outlet:, observer:)
  end

end
