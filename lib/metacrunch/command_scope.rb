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

    # Runs a job, transform or command by name or path, with params bound
    # by name; see Invoker#invoke.
    def invoke(target, params: {}, workers: nil, limit: nil) = @invoker.invoke(target, params:, workers:, limit:)

    # The root of the current project, a Pathname (see Invoker#root).
    # Raises ProjectError without project.
    def root = @invoker.root

  end
end
