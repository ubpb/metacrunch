module Metacrunch
  class Command

    attr_reader :shell
    attr_reader :options

    def initialize(shell:, options:)
      @shell   = shell
      @options = options
      setup if self.respond_to?(:setup)
    end

  end
end
