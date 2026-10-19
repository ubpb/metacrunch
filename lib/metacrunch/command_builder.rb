# frozen_string_literal: true

module Metacrunch
  # Evaluates a command recipe with instance_exec: params { ... } declares
  # the parameters (first statement), run { ... } the body (exactly one).
  # #build returns a Command::Prepared.
  class CommandBuilder

    include RecipeParams

    def initialize(binder:, describe: false, root: nil)
      init_params(binder, describe, root)
      @body = nil
    end

    def run(&body)
      use!
      raise ArgumentError, "run needs a block" unless body
      raise ArgumentError, "run is declared twice; a command has one body" if @body

      @body = body
      nil
    end

    def build
      ensure_params_bound
      raise ArgumentError, "a command needs run { ... }" unless @body

      Command::Prepared.new(params: @values, body: @body)
    end

    private

    def recipe_kind = "command"

  end
end
