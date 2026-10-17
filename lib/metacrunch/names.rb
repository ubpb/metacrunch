# frozen_string_literal: true

module Metacrunch
  # Names of jobs, transforms and commands, and their descriptions. A name
  # is one or more parts of a-z, 0-9, _ and -, separated by ":" ("a2c",
  # "es:create-index"). In a project, jobs, transforms, commands and the
  # built-in commands share one namespace.
  module Names

    PATTERN = /\A[a-z0-9][a-z0-9_-]*(?::[a-z0-9][a-z0-9_-]*)*\z/
    # The built-in commands of the CLI.
    RESERVED = ["run", "check", "trace", "new", "credentials", "help"].freeze

    module_function

    def valid?(name) = name.is_a?(String) && PATTERN.match?(name)

    # The name as a String; kind ("job", "transform", "command") is for the
    # message. Raises ArgumentError for anything but a valid String or
    # Symbol.
    def check!(name, kind)
      text = name.to_s if name.is_a?(String) || name.is_a?(Symbol)
      return text if valid?(text)

      raise ArgumentError, "invalid #{kind} name #{name.inspect}: use a-z, 0-9, _ and -, in parts separated by :"
    end

    # A description for the list in `metacrunch --help`: nil or one line.
    def check_desc!(desc)
      return desc if desc.nil? || (desc.is_a?(String) && !desc.match?(/[\r\n]/))

      raise ArgumentError, "desc must be one line of text, got #{desc.inspect}"
    end

    def reserved?(name) = RESERVED.include?(name)

    # True if argument is a path: it contains / or ., which no name does.
    def path?(argument) = argument.include?("/") || argument.include?(".")

  end
end
