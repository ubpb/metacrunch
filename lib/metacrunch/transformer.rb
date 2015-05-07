module Metacrunch
  class Transformer
    require_relative "./transformer/step"

    attr_reader :source, :target, :options

    def initialize(source:, target:, options: {})
      @source  = source
      @target  = target
      @options = options
    end

    def transform(step_class = nil, &block)
      if block_given?
        Step.new(self).instance_eval(&block) # TODO: Benchmark this
      else
        raise ArgumentError, "You need to provide a STEP or a block" if step_class.nil?
        step_class.new(self).perform
      end
    end

  end
end
