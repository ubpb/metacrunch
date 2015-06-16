module Metacrunch
  class Transformer
    require_relative "./transformer/step"
    require_relative "./transformer/helper"

    attr_accessor :source, :target, :options


    def initialize(source:nil, target:nil, options: {})
      @source  = source
      @target  = target
      @options = options
    end

    def transform(step_class = nil, &block)
      if block_given?
        Step.new(self).instance_eval(&block)
      else
        raise ArgumentError, "You need to provide a STEP or a block" if step_class.nil?
        step_class.new(self).perform
      end
    end

    def helper
      @helper ||= Helper.new(self)
    end

    def register_helper(helper_module)
      raise ArgumentError, "Must be a module" unless helper_module.is_a?(Module)
      helper.class.send(:include, helper_module) # TODO: Benchmark this
    end

  end
end
