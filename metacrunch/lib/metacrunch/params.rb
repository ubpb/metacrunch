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

    Definition = Data.define(:name, :type, :default, :required, :env, :desc, :short, :credential, :secret) do
      def option = "--#{name.to_s.tr("_", "-")}"

      # A parameter declared with secret (or with credential:) is secret:
      # its value is hidden in help texts, error messages and inspect.
      def secret? = secret || !credential.nil?

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
    # when its value is needed. credential: a path in the credentials
    # ("catalog.api_key"); it makes the parameter secret.
    def param(name, type = String, default: nil, required: false, env: nil, desc: nil, short: nil, credential: nil)
      declare(name, type, default:, required:, env:, desc:, short:, credential:, secret: false)
    end

    # A secret parameter: hidden in help texts, error messages and inspect,
    # also where use or invoke pass it on. Its default can only be a
    # reference.
    def secret(name, type = String, default: nil, required: false, desc: nil, short: nil)
      declare(name, type, default:, required:, env: nil, desc:, short:, credential: nil, secret: true)
    end

    def args(name, min: 0, max: nil, desc: nil)
      raise ArgumentError, "args can only be declared once" if @args_definition

      name = check_name!(name)
      raise ArgumentError, "args #{name}: min must not be greater than max" if max && min > max

      @args_definition = ArgsDefinition.new(name:, min:, max:, desc:)
      nil
    end

    # Binds CLI arguments. A parameter without a value on the command line
    # is read from the params file (a ParamsFile, its default: section with
    # that of environment merged over it), then from its env: variable
    # (empty counts as unset), then from the credentials (a
    # Credentials::Store, asked only now), then the default. warn is called
    # with a message for a secret given on the command line.
    def bind_argv(argv, env: ENV, credentials: nil, warn: nil, file: nil, environment: nil)
      given = {}
      positional = option_parser(given).parse(argv)
      check_file!(file) if file
      selection = file&.select(environment)
      secrets = []
      values = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, warn, selection:, secrets:)]
      end
      build(values, positional, secrets:)
    rescue OptionParser::ParseError => e
      # Without "=value" and without cause: a mistyped option may carry a
      # secret (--api-ky=...).
      raise ParamError, "#{e.reason}: #{e.args.map { it.sub(/=.*/m, "") }.join(" ")}", cause: nil
    end

    # Binds values from code: use, invoke, Project#invoke, Job#run and, with
    # an empty environment and no credentials, Testing. A value may have the
    # declared type or be a String, which is converted; a Pathname counts as
    # its path; nil means "not given". A parameter without a value is read
    # from its env: variable, then from the credentials, then the default.
    # The values come from code, so messages name a parameter by its name,
    # not as option, and a secret gives no warning. Raises ArgumentError for
    # a non-Hash and an unknown key.
    def bind_values(values, env: ENV, credentials: nil)
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
      bound = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, nil, keyword: true)]
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

    def help
      lines = option_parser({}).summarize
      lines << "    #{args_usage}\n" if @args_definition
      lines.join
    end

    private

    def declare(name, type, default:, required:, env:, desc:, short:, credential:, secret:)
      name = check_name!(name)
      raise ArgumentError, "unsupported type #{type.inspect} for parameter #{name}" unless TYPES.include?(type)
      raise ArgumentError, "parameter #{name}: #{RESERVED_SHORT} is reserved for help" if short == RESERVED_SHORT
      raise ArgumentError, "parameter #{name}: use either default: or required: true" if required && !default.nil?

      check_credential!(name, credential)
      definition = Definition.new(name:, type:, default: nil, required:, env:, desc:, short:, credential:, secret:)
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

    def check_credential!(name, path)
      return if path.nil? || (path.is_a?(String) && CREDENTIAL_PATH.match?(path))

      raise ArgumentError, "parameter #{name}: credential must be a path like \"catalog.api_key\", got #{path.inspect}"
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

      frozen_copy(convert(definition, default), secret: definition.secret?)
    rescue ParamError
      expected = TYPE_NAMES.fetch(definition.type)
      shown = definition.secret? ? HIDDEN : default.inspect
      # No cause: the converter's error would repeat the value.
      raise ArgumentError, "invalid default for parameter #{definition.name}: #{shown} is not #{expected}", cause: nil
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
      notes << "env: #{definition.env}" if definition.env
      notes << "credential: #{definition.credential}" if definition.credential
      text = [definition.desc, ("(#{notes.join(", ")})" if notes.any?)].compact.join(" ")
      text unless text.empty?
    end

    def env_value(definition, env)
      return unless definition.env && env

      value = env[definition.env]
      value unless value.nil? || value.empty?
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

    # Every key of every section of the params file must name a parameter;
    # the arguments come from the command line only.
    def check_file!(file)
      known = @definitions.keys.map(&:to_s)
      check_flat_file!(file, known)
      file.each_key do |section, key|
        where = "#{file.path}: #{section}.#{key}"
        raise ParamError, "#{where}: arguments cannot be given in a params file" if key == @args_definition&.name&.to_s
        next if known.include?(key)

        raise ParamError, "#{where}: unknown parameter (known: #{known.empty? ? "none" : known.join(", ")})"
      end
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
    # in it counts as not given. secrets collects the names of parameters
    # whose value a reference in the file took from the credentials.
    def bind(definition, given, env, credentials, warn, keyword: false, selection: nil, secrets: nil)
      if given.key?(definition.name)
        warn&.call(secret_warning(definition)) if definition.secret?
        return resolve(definition, given[definition.name], keyword:)
      end

      value, section = selection&.fetch(definition.name.to_s)
      return file_value(definition, value, section, selection, credentials:, warn:, secrets:) unless value.nil?

      raw = env_value(definition, env)
      return resolve(definition, raw, origin: "environment variable #{definition.env}", keyword:) unless raw.nil?

      raw = credentials&.lookup(definition.credential) if definition.credential
      return resolve(definition, raw, origin: credentials.origin(definition.credential), keyword:) unless raw.nil?

      default = definition.default
      return reference_value(definition, default, "default:", env, credentials) if default.is_a?(Reference)

      resolve(definition, nil, sources: -> { sources(definition, credentials) }, keyword:)
    end

    # A value of the params file: text or a list, converted like a
    # command-line value, or a reference, resolved through the credentials
    # and hidden in messages and inspect.
    def file_value(definition, value, section, selection, credentials:, warn:, secrets:)
      unless value.is_a?(ParamsFile::Reference)
        warn&.call(file_secret_warning(definition, selection)) if definition.secret?
        return resolve(definition, value, origin: "#{selection.path} (#{section})", keyword: true)
      end

      raw = credentials&.lookup(value.path)
      if raw.nil?
        detail = credentials ? credentials.missing(value.path) : "no credentials"
        raise ParamError, "#{definition.name} from #{selection.path} (#{section}): #{detail}"
      end
      secrets << definition.name
      resolve(definition, raw, origin: credentials.origin(value.path), keyword: true, hidden: true)
    end

    def file_secret_warning(definition, selection)
      "#{definition.name} is a secret; refer to it in #{selection.path} as {credential: #{definition.credential}}"
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
      "#{definition.option} is a secret; give it in a params file as {credential: PATH} or {env: NAME}"
    end

    # hidden: whether messages hide the value, as for a secret.
    def resolve(definition, raw, origin: nil, sources: nil, keyword: false, hidden: definition.secret?)
      value = if raw.nil?
        definition.default
      else
        frozen_copy(convert(definition, raw, origin:, keyword:, hidden:), secret: definition.secret?)
      end
      return value unless definition.required && value.nil?

      detail = sources&.call
      raise ParamError, "missing required parameter #{label(definition, keyword)}#{" (#{detail})" if detail}"
    end

    def convert(definition, raw, origin: nil, keyword: false, hidden: definition.secret?)
      raw = path_string(raw)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      value = value.to_f if definition.type == Float && value.is_a?(Integer)
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw, origin, keyword:, hidden:)
    rescue ArgumentError, TypeError
      invalid!(definition, raw, origin, keyword:, hidden:)
    end

    # A Pathname (anything with to_path) counts as the String of its path,
    # also inside an Array.
    def path_string(value)
      return value.to_path if value.respond_to?(:to_path)
      return value.map { path_string(it) } if value.is_a?(Array)

      value
    end

    # No cause: the converter's error (Integer(), Float(), "not a boolean")
    # would repeat a hidden value.
    def invalid!(definition, raw, origin, keyword: false, hidden: definition.secret?)
      expected = (keyword && !raw.is_a?(String) ? VALUE_TYPE_NAMES : TYPE_NAMES).fetch(definition.type)
      from = origin ? " from #{origin}" : ""
      shown = hidden ? HIDDEN : raw.inspect
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

    # secrets: parameters that are secret in this binding only.
    def build(values, positional, secrets: [])
      if @args_definition
        check_args!(positional)
        values[@args_definition.name] = frozen_copy(positional)
      elsif positional.any?
        raise ParamError, "unexpected arguments: #{positional.join(" ")}"
      end
      secret_class(secrets).new(**values)
    end

    # The values class, or for secrets beyond the declared ones a subclass
    # that also hides them (one per set of names). Data compares classes, so
    # such values are not == to equal values of the base class; to_h is.
    def secret_class(secrets)
      base = values_class
      # From the definitions: a SECRETS constant could also be a top-level one.
      declared = @definitions.values.select(&:secret?).map(&:name)
      extra = secrets - declared
      return base if extra.empty?

      @secret_classes ||= {}
      @secret_classes[extra.sort] ||= Class.new(base) do
        const_set(:SECRETS, (declared + extra).freeze)
        include Redacted
      end
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
