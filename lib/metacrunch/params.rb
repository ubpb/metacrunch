# frozen_string_literal: true

require "optparse"

module Metacrunch
  # The parameters a job declares in `params { ... }`, and their binding
  # from CLI arguments (#bind_argv) or a Hash (#bind_hash). Bound values
  # are frozen.
  class Params

    TYPES = [String, Integer, Float, :bool, Array].freeze
    # Used by the CLI for the job's help. Names of methods of the bound
    # params object (to_h, with, ...) are checked when a parameter is
    # declared.
    RESERVED = [:help].freeze
    RESERVED_SHORT = "-h"
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

    CREDENTIAL_PATH = /\A[^.]+(\.[^.]+)*\z/
    HIDDEN = "(hidden)"
    QUOTE_HINT = "quote it in the credentials file"

    # Shows secret parameters as [secret] in inspect, to_s and pp. The
    # values class defines SECRETS.
    module Redacted

      def inspect
        fields = to_h.map do |name, value|
          "#{name}=#{self.class::SECRETS.include?(name) ? "[secret]" : value.inspect}"
        end
        "#<data #{fields.join(", ")}>"
      end

      def to_s = inspect

      def pretty_print(printer) = printer.text(inspect)

    end

    Definition = Data.define(:name, :type, :default, :required, :env, :desc, :short, :credential) do
      def option = "--#{name.to_s.tr("_", "-")}"

      # A parameter with credential: is secret: its value is hidden in
      # help texts, error messages and inspect.
      def secret? = !credential.nil?
    end

    ArgsDefinition = Data.define(:name, :min, :max, :desc)

    attr_reader :definitions, :args_definition

    def initialize
      @definitions = {}
      @args_definition = nil
    end

    # Defaults are converted and checked like CLI values when the parameter
    # is declared, so a wrong default fails early. credential: a path in
    # the credentials ("catalog.api_key"); it makes the parameter secret.
    def param(name, type = String, default: nil, required: false, env: nil, desc: nil, short: nil, credential: nil)
      name = check_name!(name)
      raise ArgumentError, "unsupported type #{type.inspect} for parameter #{name}" unless TYPES.include?(type)
      raise ArgumentError, "parameter #{name}: #{RESERVED_SHORT} is reserved for help" if short == RESERVED_SHORT
      raise ArgumentError, "parameter #{name}: use either default: or required: true" if required && !default.nil?

      check_credential!(name, credential)
      definition = Definition.new(name:, type:, default: nil, required:, env:, desc:, short:, credential:)
      @definitions[name] = definition.with(default: default_value(definition, default))
      nil
    end

    def args(name, min: 0, max: nil, desc: nil)
      raise ArgumentError, "args can only be declared once" if @args_definition

      name = check_name!(name)
      raise ArgumentError, "args #{name}: min must not be greater than max" if max && min > max

      @args_definition = ArgsDefinition.new(name:, min:, max:, desc:)
      nil
    end

    # Binds CLI arguments. A parameter without a value on the command line
    # is read from its env: variable (empty counts as unset), then from the
    # credentials (a Credentials::Store, asked only now), then the default.
    # warn is called with a message for a secret given on the command line.
    def bind_argv(argv, env: ENV, credentials: nil, warn: nil)
      given = {}
      positional = option_parser(given).parse(argv)
      values = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, warn)]
      end
      build(values, positional)
    rescue OptionParser::ParseError => e
      # Without "=value" and without cause: a mistyped option may carry a
      # secret (--api-ky=...).
      raise ParamError, "#{e.reason}: #{e.args.map { it.sub(/=.*/m, "") }.join(" ")}", cause: nil
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

    # True if argv asks for help: -h or --help as an option, not as the
    # value of another option.
    def help_requested?(argv)
      help = false
      parser = option_parser({})
      parser.on("-h", "--help") { help = true }
      parser.parse(argv)
      help
    rescue OptionParser::ParseError
      help
    end

    def help
      lines = option_parser({}).summarize
      lines << "    #{args_usage}\n" if @args_definition
      lines.join
    end

    private

    def check_name!(name)
      name = name.to_sym
      raise ArgumentError, "parameter name #{name} is reserved for the CLI" if RESERVED.include?(name)
      raise ArgumentError, "parameter name #{name} would hide params.#{name}" if Data.public_method_defined?(name)
      if @definitions.key?(name) || @args_definition&.name == name
        raise ArgumentError, "parameter #{name} is declared twice"
      end

      name
    end

    def check_credential!(name, path)
      return if path.nil? || (path.is_a?(String) && CREDENTIAL_PATH.match?(path))

      raise ArgumentError, "parameter #{name}: credential must be a path like \"catalog.api_key\", got #{path.inspect}"
    end

    def default_value(definition, default)
      return if default.nil?

      frozen_copy(convert(definition, default))
    rescue ParamError
      expected = TYPE_NAMES.fetch(definition.type)
      shown = definition.secret? ? HIDDEN : default.inspect
      # No cause: the converter's error would repeat the value.
      raise ArgumentError, "invalid default for parameter #{definition.name}: #{shown} is not #{expected}", cause: nil
    end

    def option_parser(given)
      OptionParser.new do |parser|
        # Remove the built-in --help and --version: they would print and exit.
        parser.base.long.clear
        # No abbreviations: --ind must not silently mean --index.
        parser.require_exact = true
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
      notes << "secret" if definition.secret?
      notes << "default: #{definition.default}" unless definition.default.nil? || definition.secret?
      notes << "env: #{definition.env}" if definition.env
      notes << "credential: #{definition.credential}" if definition.credential
      text = [definition.desc, ("(#{notes.join(", ")})" if notes.any?)].compact.join(" ")
      text unless text.empty?
    end

    def env_value(definition, env)
      return unless definition.env

      value = env[definition.env]
      value unless value.nil? || value.empty?
    end

    def bind(definition, given, env, credentials, warn)
      if given.key?(definition.name)
        warn&.call(secret_warning(definition)) if definition.secret?
        return resolve(definition, given[definition.name])
      end

      raw = env_value(definition, env)
      return resolve(definition, raw, origin: "environment variable #{definition.env}") unless raw.nil?

      raw = credentials&.lookup(definition.credential) if definition.credential
      unless raw.nil?
        return resolve(definition, raw, origin: credentials.origin(definition.credential), hint: QUOTE_HINT)
      end

      resolve(definition, nil, sources: -> { sources(definition, credentials) })
    end

    # What was tried for a missing value, e.g. "CATALOG_API_KEY unset;
    # catalog.api_key not in FILE"; nil for a parameter without env: and
    # credential:.
    def sources(definition, credentials)
      tried = []
      tried << "#{definition.env} unset" if definition.env
      if definition.credential
        tried << (credentials ? credentials.missing(definition.credential) : "#{definition.credential}: no credentials")
      end
      tried.join("; ") unless tried.empty?
    end

    def secret_warning(definition)
      by = definition.env ? "#{definition.env} or credentials" : "credentials"
      "#{definition.option} is a secret; pass it by #{by} instead"
    end

    def resolve(definition, raw, origin: nil, hint: nil, sources: nil)
      value = raw.nil? ? definition.default : frozen_copy(convert(definition, raw, origin:, hint:))
      return value unless definition.required && value.nil?

      detail = sources&.call
      raise ParamError, "missing required parameter #{definition.option}#{" (#{detail})" if detail}"
    end

    def convert(definition, raw, origin: nil, hint: nil)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      value = value.to_f if definition.type == Float && value.is_a?(Integer)
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw, origin, hint)
    rescue ArgumentError, TypeError
      invalid!(definition, raw, origin, hint)
    end

    # The hint applies to values that YAML did not read as Strings (no,
    # 0123) where a String is expected. No cause: the converter's error
    # (Integer(), Float(), "not a boolean") would repeat a hidden value.
    def invalid!(definition, raw, origin, hint = nil)
      expected = TYPE_NAMES.fetch(definition.type)
      from = origin ? " from #{origin}" : ""
      shown = definition.secret? ? HIDDEN : raw.inspect
      note = hint && definition.type == String && !raw.is_a?(String) ? "; #{hint}" : ""
      raise ParamError, "invalid value for #{definition.option}#{from}: #{shown} is not #{expected}#{note}", cause: nil
    end

    # Bound values are frozen, so a default Array cannot leak changes from
    # one run into the next.
    def frozen_copy(value)
      case value
      when Array then value.map { |item| frozen_copy(item) }.freeze
      when String then -value
      else value
      end
    end

    def build(values, positional)
      if @args_definition
        check_args!(positional)
        values[@args_definition.name] = frozen_copy(positional)
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
      @values_class ||= begin
        klass = Data.define(*@definitions.keys, *[@args_definition&.name].compact)
        secrets = @definitions.values.select(&:secret?).map(&:name)
        if secrets.any?
          klass.const_set(:SECRETS, secrets.freeze)
          klass.include(Redacted)
        end
        klass
      end
    end

  end
end
