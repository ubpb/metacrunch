module Metacrunch
  class Command

    attr_reader :shell
    attr_reader :options
    attr_reader :params

    def initialize(shell, options = {}, params = [])
      @shell   = shell
      @options = options
      @params  = params
    end

    def pre_perform
      # can be implemented in sub-class
    end

    def perform
      raise NotImplementedError, "You must implement .perform() in your command sub-class"
    end

    def post_perform
      # can be implemented in sub-class
    end

  end
end
