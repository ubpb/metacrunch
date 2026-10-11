# frozen_string_literal: true

module Metacrunch
  # Evaluates a job recipe with instance_exec and collects what the DSL
  # declares. #build returns the Pipeline.
  class Builder

    # Thrown in describe mode with the Params schema as soon as it is known.
    DESCRIBED = :metacrunch_described
    ON_ERROR_POLICIES = [:abort, :skip].freeze

    attr_reader :logger

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    def initialize(binder:, logger:, describe: false)
      @binder = binder
      @logger = logger
      @describe = describe
      @schema = nil
      @values = nil
      @used = false
      @source = nil
      @id_extractor = nil
      @steps = []
      @sinks = {}
      @on_error = :abort
      @max_errors = nil
      @profile = false
      @before_hooks = []
      @after_hooks = []
    end

    # With a block: declares the parameters (must be the first statement).
    # Without a block: returns the bound values.
    def params(&declaration)
      return bound_params unless declaration
      raise ArgumentError, "params { ... } must be the first statement of a job" if @used || @schema

      @schema = Params.new
      @schema.instance_exec(&declaration)
      bind_schema
    end

    def source(enumerable, id: nil)
      use!
      raise ArgumentError, "source already defined" if @source
      unless enumerable.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{enumerable.inspect}"
      end

      @id_extractor = id && Callable.ensure_callable!(id, "id:")
      @source = enumerable
      nil
    end

    def map(callable = nil, name: nil, &block)
      add_step(:map, nil, callable, block, name)
    end

    def flat_map(callable = nil, name: nil, &block)
      add_step(:flat_map, nil, callable, block, name)
    end

    # filter { ... }, filter(callable), filter("reason") { ... }, filter("reason", callable)
    def filter(reason_or_callable = nil, callable = nil, name: nil, &block)
      reason, callable = split_reason(reason_or_callable, callable)
      add_step(:filter, reason, callable, block, name)
    end

    # Same arguments as filter.
    def reject(reason_or_callable = nil, callable = nil, name: nil, &block)
      reason, callable = split_reason(reason_or_callable, callable)
      add_step(:reject, reason, callable, block, name)
    end

    def sink(object, batch: nil)
      add_sink(:sink, object, batch)
    end

    def rejects(object, batch: nil)
      add_sink(:rejects, object, batch)
    end

    def errors(object, batch: nil)
      add_sink(:errors, object, batch)
    end

    def on_error(policy, max_errors: nil)
      use!
      unless ON_ERROR_POLICIES.include?(policy)
        raise ArgumentError, "on_error must be one of #{ON_ERROR_POLICIES.inspect}, got #{policy.inspect}"
      end
      unless max_errors.nil? || (policy == :skip && max_errors.is_a?(Integer) && !max_errors.negative?)
        raise ArgumentError, "max_errors must be a non-negative Integer and needs on_error :skip"
      end

      @on_error = policy
      @max_errors = max_errors
      nil
    end

    def profile(enabled)
      use!
      @profile = enabled == true
      nil
    end

    def before(&hook)
      add_hook(@before_hooks, "before", hook)
    end

    def after(&hook)
      add_hook(@after_hooks, "after", hook)
    end

    def build
      ensure_params_bound
      raise ArgumentError, "a job needs a source" unless @source

      Pipeline.new(
        source: @source, id_extractor: @id_extractor, steps: @steps.dup.freeze,
        sink: @sinks[:sink], rejects: @sinks[:rejects], errors: @sinks[:errors],
        on_error: @on_error, max_errors: @max_errors, profile: @profile,
        before_hooks: @before_hooks.dup.freeze, after_hooks: @after_hooks.dup.freeze,
        params: @values, logger: @logger
      )
    end

    private

    def bound_params
      use!
      @values
    end

    # Every DSL statement calls this. In describe mode the first statement
    # ends the evaluation; otherwise jobs without params get an empty schema.
    def use!
      ensure_params_bound
      @used = true
      nil
    end

    def ensure_params_bound
      return if @schema

      @schema = Params.new
      bind_schema
    end

    def bind_schema
      throw DESCRIBED, @schema if @describe

      @values = @binder.call(@schema)
    end

    def split_reason(first, second)
      if first.is_a?(String) || first.is_a?(Symbol)
        raise ArgumentError, "the reason must not be empty" if first.empty?

        return [first.to_s, second]
      end
      raise ArgumentError, "the reason must be a String or Symbol, got #{first.inspect}" unless second.nil?

      [nil, first]
    end

    def add_step(kind, reason, callable, block, name)
      use!
      raise ArgumentError, "#{kind}: pass a callable or a block, not both" if callable && block

      implementation = callable || block
      raise ArgumentError, "#{kind}: a callable or a block is required" unless implementation

      name = (name || "#{kind}##{@steps.size + 1}").to_s
      raise ArgumentError, "the step name #{SOURCE_STEP} is reserved" if name == SOURCE_STEP
      raise ArgumentError, "duplicate step name #{name}" if @steps.any? { |step| step.name == name }

      @steps << Step.build(kind, implementation, name:, reason:)
      nil
    end

    def add_sink(role, object, batch)
      use!
      raise ArgumentError, "#{role} already defined" if @sinks.key?(role)

      @sinks[role] = SinkAdapter.new(object, batch:)
      nil
    end

    def add_hook(hooks, kind, hook)
      use!
      raise ArgumentError, "#{kind} needs a block" unless hook

      hooks << hook
      nil
    end

  end
end
