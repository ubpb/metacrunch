# frozen_string_literal: true

module PipelineHelper

  SILENT_LOGGER = Logger.new(nil)

  def build_pipeline(params: {}, logger: SILENT_LOGGER, &recipe)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash(params) }, logger:)
    builder.instance_exec(&recipe)
    builder.build
  end

  # The executor of engine and run_pipeline; ForkVariant replaces it.
  def executor = Metacrunch::Executor::Inline.new

  def engine(pipeline, **)
    Metacrunch::Engine.new(pipeline, executor:, **)
  end

  def run_pipeline(params: {}, logger: SILENT_LOGGER, &)
    engine(build_pipeline(params:, logger:, &)).run
  end

end
