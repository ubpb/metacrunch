# frozen_string_literal: true

module PipelineHelper

  SILENT_LOGGER = Logger.new(nil)

  def build_pipeline(params: {}, logger: SILENT_LOGGER, &recipe)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash(params) }, logger:)
    builder.instance_exec(&recipe)
    builder.build
  end

  def run_pipeline(params: {}, logger: SILENT_LOGGER, &)
    Metacrunch::Engine.new(build_pipeline(params:, logger:, &)).run
  end

end
