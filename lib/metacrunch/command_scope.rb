# frozen_string_literal: true

module Metacrunch
  # The receiver of a command's body (run { ... }): the bound params, the
  # logger, invoke and root. invoker is the Invoker of the call.
  class CommandScope

    attr_reader :params, :logger

    def initialize(params:, logger:, invoker:)
      @params = params
      @logger = logger
      @invoker = invoker
    end

    # Runs a job or command by name or path, with arguments as on the
    # command line; see Invoker#invoke.
    def invoke(target, *argv, workers: nil, limit: nil) = @invoker.invoke(target, *argv, workers:, limit:)

    # The root of the current project, a Pathname. Raises ProjectError
    # without project.
    def root = @invoker.root

  end
end
