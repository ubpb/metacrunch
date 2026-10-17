# frozen_string_literal: true

module Metacrunch
  # Evaluates a job or transform recipe with instance_exec and collects
  # what the DSL declares. #build returns the Pipeline.
  class Builder

    include RecipeParams

    ON_ERROR_POLICIES = [:abort, :skip].freeze

    attr_reader :logger

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    # context: the UseContext that `use` resolves and binds transforms in.
    # transform: the Transform whose recipe this builder evaluates; it
    # refuses source, sinks, error policy and profile. nil for a job.
    # stack: the transforms being evaluated, this one last (for cycles).
    def initialize(binder:, logger:, describe: false, context: nil, transform: nil, stack: [])
      init_params(binder, describe)
      @logger = logger
      @context = context
      @transform = transform
      @stack = stack
      @source = nil
      @source_declared = false
      @id_extractor = nil
      @steps = []
      @statements = 0
      @prefixes = []
      @sinks = {}
      @on_error = :abort
      @max_errors = nil
      @profile = false
      @before_hooks = []
      @after_hooks = []
    end

    # With an object: the source. With only id: the job reads the default
    # input of the CLI (JSON Lines from stdin) with this id extractor.
    def source(enumerable = nil, id: nil)
      job_only!("source")
      use!
      raise ArgumentError, "source already defined" if @source_declared
      raise ArgumentError, "source needs an object with #each or id:" if enumerable.nil? && id.nil?
      unless enumerable.nil? || enumerable.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{enumerable.inspect}"
      end

      @id_extractor = id && Callable.ensure_callable!(id, "id:")
      @source = enumerable
      @source_declared = true
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

    # Inserts the steps and hooks of a transform here. target: a Transform,
    # or its name or path; values bind its parameters (see UseContext).
    # Its steps are named with its label as prefix: normalize/map#1.
    def use(target, **values)
      use!
      raise ArgumentError, "use needs a context: build the job with Job#pipeline(context:)" unless @context

      transform = @context.transform(target)
      built = @context.evaluate(transform, values, stack: @stack)
      prefix = prefix_for(transform)
      @steps.concat(built.steps.map { it.with(name: "#{prefix}/#{it.name}") })
      @before_hooks.concat(built.before_hooks)
      @after_hooks.concat(built.after_hooks)
      @statements += 1
      nil
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
      job_only!("on_error")
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
      job_only!("profile")
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

      Pipeline.new(
        source: @source, id_extractor: @id_extractor, steps: @steps.dup.freeze,
        sink: @sinks[:sink], rejects: @sinks[:rejects], errors: @sinks[:errors],
        on_error: @on_error, max_errors: @max_errors, profile: @profile,
        before_hooks: @before_hooks.dup.freeze, after_hooks: @after_hooks.dup.freeze,
        params: @values, logger: @logger, limit: nil
      )
    end

    private

    def recipe_kind = @transform ? "transform" : "job"

    # Source, sinks, the error policy and profile belong to the job that
    # uses a transform.
    def job_only!(statement)
      return unless @transform

      raise ArgumentError,
            "transform #{@transform.label}: a transform has no #{statement}; the job that uses it decides"
    end

    def split_reason(first, second)
      if first.is_a?(String) || first.is_a?(Symbol)
        raise ArgumentError, "the reason must not be empty" if first.empty?

        return [first.to_s, second]
      end
      raise ArgumentError, "the reason must be a String or Symbol, got #{first.inspect}" unless second.nil?

      [nil, first]
    end

    # Generated names count the step statements of the recipe, use
    # included, so a transform that gains a step renames no step of the
    # job. / is reserved for the prefixes of transforms.
    def add_step(kind, reason, callable, block, name)
      use!
      raise ArgumentError, "#{kind}: pass a callable or a block, not both" if callable && block

      implementation = callable || block
      raise ArgumentError, "#{kind}: a callable or a block is required" unless implementation

      @statements += 1
      name = (name || "#{kind}##{@statements}").to_s
      raise ArgumentError, "the step name #{SOURCE_STEP} is reserved" if name == SOURCE_STEP
      if name.include?("/")
        raise ArgumentError, "the step name #{name} contains /, which is reserved for the prefixes of transforms"
      end
      raise ArgumentError, "duplicate step name #{name}" if @steps.any? { |step| step.name == name }

      @steps << Step.build(kind, implementation, name:, reason:)
      nil
    end

    # The label of transform, numbered from its second use in this recipe:
    # normalize, normalize#2, ... A prefix is never given twice, also when
    # a label looks numbered (a file x#2.rb).
    def prefix_for(transform)
      label = transform.label
      prefix = label
      count = 1
      prefix = "#{label}##{count += 1}" while @prefixes.include?(prefix)
      @prefixes << prefix
      prefix
    end

    def add_sink(role, object, batch)
      job_only!(role.to_s)
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
