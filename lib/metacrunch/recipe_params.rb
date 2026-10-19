# frozen_string_literal: true

module Metacrunch
  # The parameters of a recipe, for Builder (jobs) and CommandBuilder
  # (commands). `params { ... }` declares them as the first statement and
  # binds them, `params` returns the bound values. Includers call
  # init_params in initialize, use! in every other statement and
  # ensure_params_bound before they build, and define recipe_kind. root
  # gives the project root in statements, hooks and steps.
  module RecipeParams

    # Thrown in describe mode with the Params schema as soon as it is known.
    DESCRIBED = :metacrunch_described

    # With a block: declares the parameters (must be the first statement).
    # Without a block: returns the bound values.
    def params(&declaration)
      return bound_params unless declaration
      raise ArgumentError, "params { ... } must be the first statement of a #{recipe_kind}" if @used || @schema

      @schema = Params.new(root: @root)
      @schema.instance_exec(&declaration)
      bind_schema
    end

    # The root of the project the recipe runs in, a Pathname: in
    # statements, hooks and steps. Raises ProjectError if the call has no
    # project.
    def root
      raise ProjectError, Params::NO_ROOT unless @root

      @root.call
    end

    private

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    # root: a callable that returns the project root (see Invoker#root),
    # or nil.
    def init_params(binder, describe, root = nil)
      @binder = binder
      @describe = describe
      @root = root
      @schema = nil
      @values = nil
      @used = false
    end

    def bound_params
      use!
      @values
    end

    # Every statement calls this. In describe mode the first statement ends
    # the evaluation; otherwise recipes without params get an empty schema.
    def use!
      ensure_params_bound
      @used = true
      nil
    end

    def ensure_params_bound
      return if @schema

      @schema = Params.new(root: @root)
      bind_schema
    end

    def bind_schema
      throw DESCRIBED, @schema if @describe

      @values = @binder.call(@schema)
    end

  end
end
