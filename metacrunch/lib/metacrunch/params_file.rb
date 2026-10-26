# frozen_string_literal: true

module Metacrunch
  # A params file (--params): parameter values in a default: section and one
  # section per environment. A value is text, a list of texts, null (not
  # given) or {credential: PATH}. load checks the structure; Params checks
  # the keys against the declared parameters (see docs/jobs.md).
  class ParamsFile

    DEFAULT = "default"
    FORMS = "a value must be text, a list or {credential: PATH}"

    # A value that refers to the credentials.
    Reference = Data.define(:path)

    # The values of one environment, name => [value, section], the sections
    # they came from and the path of the file.
    Selection = Data.define(:path, :values, :sections) do
      # [value, section], or nil if no section has the name.
      def fetch(name) = values[name]
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

    # The values of environment (nil for none) merged over those of
    # default:. Raises ParamError for an environment without a section if
    # the file has any environment section.
    def select(environment)
      names = [DEFAULT]
      if @sections.key?(environment)
        names << environment
      elsif environment && @sections.keys.any? { it != DEFAULT }
        raise ParamError,
              "#{@path} has no section for environment #{environment} (sections: #{@sections.keys.join(", ")})"
      end
      names &= @sections.keys
      values = {}
      names.each { |name| @sections.fetch(name).each { |key, value| values[key] = [value, name] } }
      Selection.new(path: @path, values:, sections: names)
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
      raise ParamError, "#{@path}: section #{name} must be a mapping of parameters" unless values.is_a?(Hash)

      values.to_h { |key, value| [key.to_s, value(name, key, value)] }
    end

    def value(section, key, value)
      return value if value.nil? || value.is_a?(String)
      return reference(section, key, value) if value.is_a?(Hash)
      return value if value.all? { it.nil? || it.is_a?(String) }

      raise ParamError, "#{@path}: #{section}.#{key}: #{FORMS}"
    end

    def reference(section, key, value)
      raise ParamError, "#{@path}: #{section}.#{key}: #{FORMS}" unless value.keys == ["credential"]

      path = value.fetch("credential")
      return Reference.new(path:) if path.is_a?(String) && Params::CREDENTIAL_PATH.match?(path)

      raise ParamError,
            %(#{@path}: #{section}.#{key}: credential must be a path like "catalog.api_key", got #{path.inspect})
    end

  end
end
