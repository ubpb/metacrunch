# frozen_string_literal: true

module Metacrunch
  # A params file (--params): the parameter values of each environment, in
  # one section per environment (default: for the default environment); a
  # section inherits nothing unless it says so with YAML merge keys. A
  # value is text, a list of texts, null (not given) or a reference
  # ({credential: PATH}, {env: NAME}; see Params::Reference). load checks
  # the structure; Params checks the keys and values against the declared
  # parameters (see docs/jobs.md).
  class ParamsFile

    DEFAULT = "default"
    FORMS = "a value must be text, a list, {credential: PATH} or {env: NAME}"
    # For files without sections, whose parameters stand at the top level.
    SECTIONS_HINT = "parameters go under default: or an environment section"

    # The section of one environment: its values (name => value), its name
    # and the path of the file.
    Selection = Data.define(:path, :section, :values) do
      def [](name) = values[name]

      def key?(name) = values.key?(name)

      # "FILE (section)", as messages and the log name it.
      def to_s = "#{path} (#{section})"
    end

    attr_reader :path

    # path as given on the command line; messages name it so.
    def self.load(path) = new(path, Credentials.parse_yaml(read(path), path, error: ParamError))

    def self.read(path)
      File.read(path)
    rescue Errno::ENOENT
      raise ParamError, "params file not found: #{path}", cause: nil
    rescue SystemCallError => e
      raise ParamError, "cannot read params file #{path}: #{e.message.split(" @ ").first}", cause: nil
    end
    private_class_method :read

    def initialize(path, data)
      @path = path
      @sections = sections(data)
    end

    # Yields section and key of every value, in every section.
    def each_key
      @sections.each { |section, values| values.each_key { yield section, it } }
    end

    # The keys of every section, also of empty ones: name => [key, ...].
    def keys_by_section = @sections.transform_values(&:keys)

    # The section of environment, default: for nil (the default
    # environment); nothing is merged from other sections. Raises ParamError
    # if the file has no such section.
    def select(environment)
      name = environment || DEFAULT
      unless @sections.key?(name)
        sections = @sections.empty? ? "none" : @sections.keys.join(", ")
        raise ParamError, "#{@path} has no section #{name} (sections: #{sections})"
      end

      Selection.new(path: @path, section: name, values: @sections.fetch(name))
    end

    # Yields section, key and value of every value, in every section.
    def each_value
      @sections.each { |section, values| values.each { |key, value| yield section, key, value } }
    end

    private

    def sections(data)
      return {} if data.nil?
      unless data.is_a?(Hash)
        raise ParamError, "#{@path} must contain a mapping of sections (default: and environments) at the top level"
      end

      data.to_h { |name, values| [section_name(name), section(name, values)] }
    end

    def section_name(name)
      return name if name == DEFAULT || (name.is_a?(String) && Credentials::ENVIRONMENT_NAME.match?(name))

      raise ParamError,
            "#{@path}: invalid section #{name.inspect}: use default or an environment name (a-z, 0-9, _ and -)"
    end

    def section(name, values)
      return {} if values.nil?
      unless values.is_a?(Hash)
        raise ParamError, "#{@path}: section #{name} must be a mapping of parameters (#{SECTIONS_HINT})"
      end

      values.to_h { |key, value| [key.to_s, value(name, key, value)] }
    end

    def value(section, key, value)
      return value if value.nil? || value.is_a?(String)
      return reference(section, key, value) if value.is_a?(Hash)
      # Tags still give other objects: !!float a Float, !ruby/encoding an Encoding.
      return value if value.is_a?(Array) && value.all? { it.nil? || it.is_a?(String) }

      raise ParamError, "#{@path}: #{section}.#{key}: #{FORMS}"
    end

    # A Params::Reference; a mapping of one key credential or env that is
    # no reference names what is wrong with it.
    def reference(section, key, value)
      where = "#{@path}: #{section}.#{key}"
      raise ParamError, "#{where}: #{FORMS}" unless value.size == 1 && Params::REFERENCE_SOURCES.key?(value.keys.first)

      Params.reference(value)
    rescue ArgumentError
      path = value["credential"]
      raise ParamError, "#{where}: #{Params::REFERENCE_FORMS}" unless value.key?("credential")

      raise ParamError, %(#{where}: credential must be a path like "catalog.api_key", got #{path.inspect})
    end

  end
end
