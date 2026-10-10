# frozen_string_literal: true

module Metacrunch
  # Helpers for callables: blocks, lambdas, Method objects and any object
  # that responds to #call.
  module Callable

    POSITIONAL = [:req, :opt].freeze

    module_function

    # True if the callable takes a second positional argument (the context):
    # a second required or optional parameter, or a named splat. Symbol
    # procs (&:odd?) have an unnamed splat and get only the record.
    def accepts_second_argument?(callable)
      parameters = parameters_of(callable)
      return true if parameters.any? { |type, name| type == :rest && name }

      parameters.count { |type, _name| POSITIONAL.include?(type) } >= 2
    end

    def parameters_of(callable)
      case callable
      when Proc then callable.parameters(lambda: true)
      when Method then callable.parameters
      else callable.method(:call).parameters
      end
    end

    def ensure_callable!(object, role)
      return object if object.respond_to?(:call)

      raise ArgumentError, "#{role} must respond to #call, got #{object.inspect}"
    end

  end
end
