# frozen_string_literal: true

require "optparse"

module Metacrunch
  # The parameters a recipe declares in `params { ... }`, and their binding
  # from the command line (#bind_argv) or from values in code (#bind_values:
  # use, invoke, Job#run, Testing). Bound values are frozen.
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
      Array => ->(value) { value.is_a?(Array) && value.all?(String) },
      :bool => ->(value) { [true, false].include?(value) }
    }.freeze

    TYPE_NAMES = {
      String => "a String",
      Integer => "an Integer",
      Float => "a Float",
      Array => "a comma-separated list",
      :bool => "a boolean (true/false, yes/no, on/off, 1/0)"
    }.freeze

    # The types as Ruby values, for values from code that are no Strings.
    VALUE_TYPE_NAMES = TYPE_NAMES.merge(Array => "an Array of Strings", :bool => "true or false").freeze

    NO_ROOT = "root needs a project, and none was given"
    CREDENTIAL_PATH = /\A[^.]+(\.[^.]+)*\z/
    ENV_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    HIDDEN = "(hidden)"
    REFERENCE_FORMS = "a reference is {credential: PATH} or {env: NAME}"
    REFERENCE_SOURCES = {"credential" => CREDENTIAL_PATH, "env" => ENV_NAME}.freeze

    # A value that a run takes from elsewhere: {credential: PATH} from the
    # credentials, {env: NAME} from an environment variable.
    Reference = Data.define(:source, :key) do
      def to_s = "#{source} #{key}"
    end

    # The values of the secrets of bound params, for the safety net of use
    # and invoke: Strings, Arrays and their items, which a secret owns
    # (immediates such as Integers cannot be told by identity).
    def self.secret_values(bound)
      return [] unless bound.class.const_defined?(:SECRETS, false)

      bound.class::SECRETS.map { bound.public_send(it) }.flat_map do |value|
        case value
        when Array then [value, *value]
        when String then [value]
        else []
        end
      end
    end

    # The Reference that value stands for, or nil if value is no Hash.
    # Raises ArgumentError for a Hash that is no reference. Keys may be
    # Symbols (code) or Strings (YAML).
    def self.reference(value)
      return unless value.is_a?(Hash)

      source, key = value.first
      pattern = REFERENCE_SOURCES[source.to_s]
      raise ArgumentError, REFERENCE_FORMS unless value.size == 1 && pattern && key.is_a?(String) && pattern.match?(key)

      Reference.new(source: source.to_sym, key:)
    end

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

    Definition = Data.define(:name, :type, :default, :required, :desc, :short, :secret) do
      def option = "--#{name.to_s.tr("_", "-")}"

      # A parameter declared with secret: its value is hidden in help texts,
      # error messages and inspect.
      def secret? = secret

      # How declaration errors name it: "secret api_key", "parameter index".
      def label = "#{secret ? "secret" : "parameter"} #{name}"
    end

    ArgsDefinition = Data.define(:name, :min, :max, :desc)

    attr_reader :definitions, :args_definition

    # root: a callable that returns the project root, for defaults such as
    # root.join("data/titles.jsonl"); nil where there is none.
    def initialize(root: nil)
      @definitions = {}
      @args_definition = nil
      @root = root
    end

    # The root of the project, a Pathname; see Invoker#root.
    def root
      raise ProjectError, NO_ROOT unless @root

      @root.call
    end

    # Defaults are converted and checked like CLI values when the parameter
    # is declared, so a wrong default fails early; a reference
    # ({credential: PATH}, {env: NAME}) is checked for its form and resolved
    # when its value is needed; {credential: PATH} only for a secret.
    def param(name, type = String, default: nil, required: false, desc: nil, short: nil)
      declare(name, type, default:, required:, desc:, short:, secret: false)
    end

    # A secret parameter: hidden in help texts, error messages and inspect,
    # also where use or invoke pass it on. Its default can only be a
    # reference.
    def secret(name, type = String, default: nil, required: false, desc: nil, short: nil)
      declare(name, type, default:, required:, desc:, short:, secret: true)
    end

    def args(name, min: 0, max: nil, desc: nil)
      raise ArgumentError, "args can only be declared once" if @args_definition

      name = check_name!(name)
      raise ArgumentError, "args #{name}: min must not be greater than max" if max && min > max

      @args_definition = ArgsDefinition.new(name:, min:, max:, desc:)
      nil
    end

    # Binds CLI arguments. A parameter without a value on the command line
    # takes the value of the params file (a ParamsFile; its section of
    # environment, default: for nil), then its default. References are
    # resolved through env (variables) and credentials (a
    # Credentials::Store, asked only now). warn is called with a message for
    # a secret given on the command line. others: a callable that returns
    # the parameters of the other recipes the file may serve, as
    # #parameters gives them (see check_file!).
    def bind_argv(argv, env: ENV, credentials: nil, warn: nil, file: nil, environment: nil, others: nil)
      given = {}
      positional = option_parser(given).parse(argv)
      check_file!(file, others) if file
      selection = file&.select(environment)
      values = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, warn, selection:)]
      end
      build(values, positional)
    rescue OptionParser::ParseError => e
      # Without "=value", the value attached to a short option, and the
      # cause: a mistyped option may carry a secret (--api-ky=..., -Psk...).
      raise ParamError, "#{e.reason}: #{e.args.map { option_name(it) }.join(" ")}", cause: nil
    end

    # Binds values from code: use, invoke, Project#invoke, Job#run and, with
    # no environment variables (env nil) and no credentials, Testing. A value
    # may have the declared type or be a String, which is converted; a
    # Pathname counts as its path; nil means "not given". A parameter
    # without a value takes its default.
    # The values come from code, so messages name a parameter by its name,
    # not as option, and a secret gives no warning. secrets: the secret
    # values of the caller (see secret_values); passing one unchanged to a
    # parameter that is no secret raises ParamError, named for target.
    # references: false leaves a parameter whose default is a reference nil
    # without resolving it (Testing.invoke, whose targets do not run).
    # Raises ArgumentError for a non-Hash and an unknown key.
    def bind_values(values, env: ENV, credentials: nil, secrets: [], target: nil, references: true)
      raise ArgumentError, "params: must be a Hash, got #{values.inspect}" unless values.is_a?(Hash)

      values = values.transform_keys(&:to_sym)
      args_name = @args_definition&.name
      known = [*@definitions.keys, *args_name]
      unknown = values.keys - known
      if unknown.any?
        raise ArgumentError,
              "unknown parameter #{unknown.first.inspect} (known: #{known.empty? ? "none" : known.join(", ")})"
      end

      given = values.except(args_name).compact
      guard_secrets!(given, values[args_name], secrets, target)
      bound = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, nil, keyword: true, references:)]
      end
      build(bound, args_values(values[args_name]))
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

    # name => whether it is a secret, for every declared parameter, names
    # as Strings; the arguments are none.
    def parameters = @definitions.to_h { |name, definition| [name.to_s, definition.secret?] }

    def help
      lines = option_parser({}).summarize
      lines << "    #{args_usage}\n" if @args_definition
      lines.join
    end

    private

    def declare(name, type, default:, required:, desc:, short:, secret:)
      name = check_name!(name)
      raise ArgumentError, "unsupported type #{type.inspect} for parameter #{name}" unless TYPES.include?(type)
      raise ArgumentError, "parameter #{name}: #{RESERVED_SHORT} is reserved for help" if short == RESERVED_SHORT
      raise ArgumentError, "parameter #{name}: use either default: or required: true" if required && !default.nil?

      definition = Definition.new(name:, type:, default: nil, required:, desc:, short:, secret:)
      @definitions[name] = definition.with(default: default_value(definition, default))
      nil
    end

    def check_name!(name)
      name = name.to_sym
      raise ArgumentError, "parameter name #{name} is reserved for the CLI" if RESERVED.include?(name)
      raise ArgumentError, "parameter name #{name} would hide params.#{name}" if Data.public_method_defined?(name)
      if @definitions.key?(name) || @args_definition&.name == name
        raise ArgumentError, "parameter #{name} is declared twice"
      end

      name
    end

    # A plain default converted, or a Reference checked for its form and the
    # rules of secrets: credentials only for secrets, secrets only from
    # references.
    def default_value(definition, default)
      return if default.nil?

      reference = default_reference(definition, default)
      return reference if reference
      if definition.secret
        raise ArgumentError,
              "#{definition.label}: a default must be {credential: PATH} or {env: NAME}, not a plain value"
      end

      frozen_copy(convert(definition, default))
    rescue ParamError
      expected = TYPE_NAMES.fetch(definition.type)
      # No cause: the converter's error would repeat the value.
      raise ArgumentError, "invalid default for parameter #{definition.name}: #{default.inspect} is not #{expected}",
            cause: nil
    end

    def default_reference(definition, default)
      reference = Params.reference(default)
      if reference&.source == :credential && !definition.secret?
        raise ArgumentError, "#{definition.label}: a value from the credentials needs secret, not param"
      end

      reference
    rescue ArgumentError => e
      raise if e.message != REFERENCE_FORMS

      raise ArgumentError, "#{definition.label}: #{REFERENCE_FORMS}", cause: nil
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
      default = definition.default
      notes << "default: #{default}" if default.is_a?(Reference) || !(default.nil? || definition.secret?)
      text = [definition.desc, ("(#{notes.join(", ")})" if notes.any?)].compact.join(" ")
      text unless text.empty?
    end

    # The value of a reference: from the credentials or the environment.
    # from: where the reference stood ("default:", "FILE (section)"). A
    # reference that finds nothing is an error; credentials or env nil mean
    # a test, which reads neither.
    def reference_value(definition, reference, from, env, credentials)
      name = definition.name
      raw, origin = if reference.source == :credential
        credential(name, reference, credentials)
      else
        variable(name, reference, env)
      end
      raise ParamError, missing_reference(name, reference, from, credentials) if raw.nil?

      resolve(definition, raw, origin: "#{origin} via #{from.delete_suffix(":")}", keyword: true)
    end

    # "api_key: credential catalog.api_key from default: not in FILE",
    # "es_url: environment variable ES_URL from FILE (production) is not set"
    def missing_reference(name, reference, from, credentials)
      return "#{name}: environment variable #{reference.key} from #{from} is not set" if reference.source == :env

      reason = credentials.missing(reference.key).delete_prefix("#{reference.key} ")
      "#{name}: credential #{reference.key} from #{from}#{from.end_with?(":") ? " " : ": "}#{reason}"
    end

    def credential(name, reference, credentials)
      raise ParamError, "#{name}: Testing reads no credentials; pass #{name} in params:" unless credentials

      [credentials.lookup(reference.key), credentials.origin(reference.key)]
    end

    def variable(name, reference, env)
      raise ParamError, "#{name}: Testing reads no environment variables; pass #{name} in params:" if env.nil?

      value = env[reference.key]
      [(value unless value.nil? || value.empty?), "environment variable #{reference.key}"]
    end

    # A secret of the caller, passed unchanged (the same object, also in a
    # list) to a parameter that is no secret or to the arguments, would lose
    # its secrecy there.
    def guard_secrets!(given, args, secrets, target)
      return if secrets.empty?

      given.each do |name, value|
        next if @definitions.fetch(name).secret? || !holds_secret?(value, secrets)

        raise ParamError, "#{name} gets a secret, but #{target} declares it as param; declare it secret there"
      end
      return unless holds_secret?(args, secrets)

      raise ParamError,
            "#{@args_definition.name} gets a secret, but #{target} takes it as arguments, which cannot be secret"
    end

    def holds_secret?(value, secrets)
      [value, *(value if value.is_a?(Array))].any? { |part| secrets.any? { it.equal?(part) } }
    end

    # Every key of every section of the params file must name a parameter:
    # one of this recipe, else one that others declare (the other recipes
    # of the project; asked only for a key this recipe does not declare).
    # Such a key is left to them but keeps the rules of secrets. The
    # arguments come from the command line only.
    def check_file!(file, others)
      own = @definitions.keys.map(&:to_s)
      foreign_keys = file.to_enum(:each_key).any? { |_section, key| !own.include?(key) }
      foreign = foreign_keys && others ? others.call : {}
      known = own | foreign.keys
      check_flat_file!(file, known)
      file.each_key do |section, key|
        next if known.include?(key)

        where = "#{file.path}: #{section}.#{key}"
        raise ParamError, "#{where}: arguments cannot be given in a params file" if key == @args_definition&.name&.to_s

        raise ParamError, "#{where}: unknown parameter (known: #{known.empty? ? "none" : known.join(", ")})"
      end
      file.each_value do |section, key, value|
        next check_file_value!(file, section, @definitions.fetch(key.to_sym), value) if own.include?(key)

        check_secret_rules!("#{file.path}: #{section}.#{key}", key, foreign.fetch(key), value)
      end
    end

    # Every value of every section, also of sections not selected: the
    # rules of secrets, plain values convertible. References are resolved
    # only for the selected section.
    def check_file_value!(file, section, definition, value)
      check_secret_rules!("#{file.path}: #{section}.#{definition.name}", definition.name, definition.secret?, value)
      return if value.nil? || value.is_a?(Reference)

      convert(definition, value, origin: "#{file.path} (#{section})", keyword: true)
    end

    # A credential only for a secret, no plain value for one.
    def check_secret_rules!(where, name, secret, value)
      if value.is_a?(Reference)
        return unless value.source == :credential && !secret

        raise ParamError, "#{where}: a value from the credentials needs secret, not param"
      end
      return if value.nil? || !secret

      raise ParamError, "#{where}: #{name} is a secret; give it as {credential: PATH} or {env: NAME}"
    end

    # A file without sections reads a parameter at the top level (a
    # reference, a null) as a section. A section named like a parameter that
    # holds no parameter is taken for one; an environment named so is not.
    def check_flat_file!(file, known)
      file.keys_by_section.each do |section, keys|
        next if section == ParamsFile::DEFAULT || !known.include?(section) || keys.intersect?(known)

        raise ParamError, "#{file.path}: #{section} is a parameter, not a section: #{ParamsFile::SECTIONS_HINT}"
      end
    end

    # selection: the ParamsFile::Selection of the run, or nil; a null value
    # in it counts as not given.
    def bind(definition, given, env, credentials, warn, keyword: false, selection: nil, references: true)
      if given.key?(definition.name)
        warn&.call(secret_warning(definition)) if definition.secret?
        return resolve(definition, given[definition.name], keyword:)
      end

      value = selection&.[](definition.name.to_s)
      return file_value(definition, value, selection, env:, credentials:) unless value.nil?

      default = definition.default
      if default.is_a?(Reference)
        return references ? reference_value(definition, default, "default:", env, credentials) : nil
      end

      resolve(definition, nil, sources: -> { sources(definition, selection) }, keyword:)
    end

    # A value of the params file: text or a list, converted like a
    # command-line value, or a reference (see reference_value).
    def file_value(definition, value, selection, env:, credentials:)
      return reference_value(definition, value, selection.to_s, env, credentials) if value.is_a?(Reference)

      resolve(definition, value, origin: selection.to_s, keyword: true)
    end

    # Why the params file gave no value for a missing one, e.g. "null in
    # FILE (production)"; nil without a params file.
    def sources(definition, selection)
      return unless selection

      "#{selection.key?(definition.name.to_s) ? "null" : "not"} in #{selection}"
    end

    def option_name(argument)
      argument.match?(/\A-[^-]/) ? argument[0, 2] : argument.sub(/=.*/m, "")
    end

    def secret_warning(definition)
      "#{definition.option} is a secret; give it in a params file as {credential: PATH} or {env: NAME}"
    end

    def resolve(definition, raw, origin: nil, sources: nil, keyword: false)
      value = if raw.nil?
        definition.default
      else
        frozen_copy(convert(definition, raw, origin:, keyword:), secret: definition.secret?)
      end
      return value unless definition.required && value.nil?

      detail = sources&.call
      raise ParamError, "missing required parameter #{label(definition, keyword)}#{" (#{detail})" if detail}"
    end

    def convert(definition, raw, origin: nil, keyword: false)
      raw = path_string(raw)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      value = value.to_f if definition.type == Float && value.is_a?(Integer)
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw, origin, keyword:)
    rescue ArgumentError, TypeError
      invalid!(definition, raw, origin, keyword:)
    end

    # A Pathname (anything with to_path) counts as the String of its path,
    # also inside an Array.
    def path_string(value)
      return value.to_path if value.respond_to?(:to_path)
      return value.map { path_string(it) } if value.is_a?(Array)

      value
    end

    # No cause: the converter's error (Integer(), Float(), "not a boolean")
    # would repeat the value of a secret, which messages hide.
    def invalid!(definition, raw, origin, keyword: false)
      expected = (keyword && !raw.is_a?(String) ? VALUE_TYPE_NAMES : TYPE_NAMES).fetch(definition.type)
      from = origin ? " from #{origin}" : ""
      shown = definition.secret? ? HIDDEN : raw.inspect
      raise ParamError, "invalid value for #{label(definition, keyword)}#{from}: #{shown} is not #{expected}",
            cause: nil
    end

    # The args of bind_values: nil for none, a String for one, or an Array
    # of Strings, as the command line gives them.
    def args_values(value)
      value = path_string(value)
      return [] if value.nil?
      return [value] if value.is_a?(String)
      return value if value.is_a?(Array) && value.all?(String)

      raise ParamError, "invalid value for #{@args_definition.name}: #{value.inspect} is not an Array of Strings"
    end

    # How messages name a parameter: as option (--api-key) for the command
    # line, by name (api_key) for the keyword values of use.
    def label(definition, keyword) = keyword ? definition.name.to_s : definition.option

    # Bound values are frozen, so a default Array cannot leak changes from
    # one run into the next.
    # secret: an own copy instead of the deduplicated String, so the values
    # of secrets can be told by identity (see bind_values).
    def frozen_copy(value, secret: false)
      case value
      when Array then value.map { |item| frozen_copy(item, secret:) }.freeze
      when String then secret ? value.dup.freeze : -value
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
