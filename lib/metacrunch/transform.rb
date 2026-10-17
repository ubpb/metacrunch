# frozen_string_literal: true

module Metacrunch
  # A transform is a recipe of steps, hooks and parameters without source
  # and sinks. A job inserts its steps with `use`; alone it runs like a job
  # without source and sink, from stdin to stdout.
  class Transform

    attr_reader :name, :desc

    # The file the transform was loaded from, else nil. Set by Loader.
    attr_accessor :file

    # name: see Names; nil for a transform that is used by path or as an
    # object only. desc: one line for the list in `metacrunch --help`.
    def initialize(name = nil, desc: nil, &recipe)
      raise ArgumentError, "a transform needs a block" unless recipe

      @name = name.nil? ? nil : Names.check!(name, "transform")
      @desc = Names.check_desc!(desc)
      @recipe = recipe
    end

    # The name for messages and step prefixes: the name, else the base name
    # of the file, else "transform".
    def label
      return @name if @name

      file ? File.basename(file, ".rb") : "transform"
    end

    # Evaluates the recipe in transform mode. The pipeline has steps and
    # hooks, but no source and no sinks. binder: see Job#pipeline.
    # context: the UseContext for `use` in this recipe. stack: the
    # transforms whose recipes are being evaluated around this one.
    def pipeline(binder:, logger: Metacrunch.logger, context: nil, stack: [])
      builder = Builder.new(binder:, logger:, context:, transform: self, stack: [*stack, self])
      builder.instance_exec(&@recipe)
      builder.build
    end

    # The declared parameters. Evaluates the recipe only up to its first
    # statement.
    def describe
      builder = Builder.new(binder: nil, logger: Metacrunch.logger, describe: true, transform: self)
      catch(RecipeParams::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
