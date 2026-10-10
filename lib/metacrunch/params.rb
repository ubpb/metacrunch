# frozen_string_literal: true

require "optparse"

module Metacrunch
  # The parameters a job declares in `params { ... }`, and their binding
  # from CLI arguments (#bind_argv) or a Hash (#bind_hash).
  class Params

    TYPES = [String, Integer, Float, :bool, Array].freeze
    RESERVED = [:help, :job].freeze
    TRUE_VALUES = ["true", "yes", "on", "1"].freeze
    FALSE_VALUES = ["false", "no", "off", "0"].freeze

    CONVERTERS = {
      String => ->(raw) { raw },
      Integer => ->(raw) { Integer(raw, 10) },
      Float => ->(raw) { Float(raw) },
      Array => ->(raw) { raw.split(",").map(&:strip) },
      :bool => lambda do |raw|
        return true if TRUE_VALUES.include?(raw.downcase)
        return false if FALSE_VALUES.include?(raw.downcase)

        raise ArgumentError, "not a boolean: #{raw}"
      end
    }.freeze

    VALID = {
      String => ->(value) { value.is_a?(String) },
      Integer => ->(value) { value.is_a?(Integer) },
      Float => ->(value) { value.is_a?(Float) },
      Array => ->(value) { value.is_a?(Array) },
      :bool => ->(value) { [true, false].include?(value) }
    }.freeze

    TYPE_NAMES = {
      String => "a String",
      Integer => "an Integer",
      Float => "a Float",
      Array => "a comma-separated list",
      :bool => "a boolean (true/false, yes/no, on/off, 1/0)"
    }.freeze

    Definition = Data.define(:name, :type, :default, :required, :env, :desc, :short) do
      def option = "--#{name.to_s.tr("_", "-")}"
    end

    ArgsDefinition = Data.define(:name, :min, :max, :desc)

    attr_reader :definitions, :args_definition

    def initialize
      @definitions = {}
      @args_definition = nil
    end

    def param(name, type = String, default: nil, required: false, env: nil, desc: nil, short: nil)
      name = check_name!(name)
      raise ArgumentError, "unsupported type #{type.inspect} for parameter #{name}" unless TYPES.include?(type)
      raise ArgumentError, "parameter #{name}: use either default: or required: true" if required && !default.nil?

      @definitions[name] = Definition.new(name:, type:, default:, required:, env:, desc:, short:)
      nil
    end

    def args(name, min: 0, max: nil, desc: nil)
      raise ArgumentError, "args can only be declared once" if @args_definition

      name = check_name!(name)
      raise ArgumentError, "args #{name}: min must not be greater than max" if max && min > max

      @args_definition = ArgsDefinition.new(name:, min:, max:, desc:)
      nil
    end

    # Binds CLI arguments. Parameters with env: that are not given on the
    # command line are read from env.
    def bind_argv(argv, env: ENV)
      given = {}
      positional = option_parser(given).parse(argv)
      values = @definitions.to_h do |name, definition|
        [name, resolve(definition, given.fetch(name) { env_value(definition, env) })]
      end
      build(values, positional)
    rescue OptionParser::ParseError => e
      raise ParamError, e.message
    end

    # Binds a Hash, e.g. in tests. Values may already have the declared
    # type or be strings, which are converted. No environment lookup.
    def bind_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      args_name = @args_definition&.name
      unknown = hash.keys - @definitions.keys - [args_name]
      raise ParamError, "unknown parameter #{unknown.first}" if unknown.any?

      values = @definitions.to_h { |name, definition| [name, resolve(definition, hash[name])] }
      build(values, args_name ? Array(hash[args_name]) : [])
    end

    def help
      lines = option_parser({}).summarize
      lines << "    #{args_usage}\n" if @args_definition
      lines.join
    end

    private

    def check_name!(name)
      name = name.to_sym
      raise ArgumentError, "parameter name #{name} is reserved" if RESERVED.include?(name)
      if @definitions.key?(name) || @args_definition&.name == name
        raise ArgumentError, "parameter #{name} is declared twice"
      end

      name
    end

    def option_parser(given)
      OptionParser.new do |parser|
        # Remove the built-in --help and --version: they would print and exit.
        parser.base.long.clear
        @definitions.each_value do |definition|
          parser.on(*switches(definition)) { |value| given[definition.name] = value }
        end
      end
    end

    def switches(definition)
      long = if definition.type == :bool
        "--[no-]#{definition.option.delete_prefix("--")}"
      else
        "#{definition.option} VALUE"
      end
      [definition.short, long, description(definition)].compact
    end

    def description(definition)
      notes = []
      notes << "required" if definition.required
      notes << "default: #{definition.default}" unless definition.default.nil?
      notes << "env: #{definition.env}" if definition.env
      text = [definition.desc, ("(#{notes.join(", ")})" if notes.any?)].compact.join(" ")
      text unless text.empty?
    end

    def env_value(definition, env)
      env[definition.env] if definition.env
    end

    def resolve(definition, raw)
      value = raw.nil? ? definition.default : convert(definition, raw)
      raise ParamError, "missing required parameter #{definition.option}" if definition.required && value.nil?

      value
    end

    def convert(definition, raw)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw)
    rescue ArgumentError, TypeError
      invalid!(definition, raw)
    end

    def invalid!(definition, raw)
      expected = TYPE_NAMES.fetch(definition.type)
      raise ParamError, "invalid value for #{definition.option}: #{raw.inspect} is not #{expected}"
    end

    def build(values, positional)
      if @args_definition
        check_args!(positional)
        values[@args_definition.name] = positional
      elsif positional.any?
        raise ParamError, "unexpected arguments: #{positional.join(" ")}"
      end
      values_class.new(**values)
    end

    def check_args!(positional)
      definition = @args_definition
      if positional.size < definition.min
        raise ParamError,
              "expected at least #{definition.min} argument(s) for #{definition.name}, got #{positional.size}"
      end
      return unless definition.max && positional.size > definition.max

      raise ParamError, "expected at most #{definition.max} argument(s) for #{definition.name}, got #{positional.size}"
    end

    def args_usage
      definition = @args_definition
      count = if definition.max
        "#{definition.min} to #{definition.max} arguments"
      else
        "#{definition.min} or more arguments"
      end
      [definition.name.to_s.upcase, definition.desc, "(#{count})"].compact.join("  ")
    end

    def values_class
      @values_class ||= Data.define(*@definitions.keys, *[@args_definition&.name].compact)
    end

  end
end
