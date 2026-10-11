# frozen_string_literal: true

module Metacrunch
  module Credentials
    # The credentials of one Location, read and decrypted on the first lookup,
    # once. Params asks it only for values that neither the command line nor
    # an env: variable gives.
    class Store

      def initialize(location, logger: nil)
        @location = location
        @logger = logger
        @loaded = false
        @data = nil
      end

      # The value at path ("fis.api_key"), or nil. Raises CredentialsError if
      # the credentials cannot be read.
      def lookup(path)
        data = load
        data && path.split(".").reduce(data) { |node, key| node.is_a?(Hash) ? node[key] : nil }
      end

      # Where a value came from, for messages.
      def origin(path) = "credential #{path} in #{@location.file}"

      # Why path has no value, for the message about a missing parameter.
      def missing(path)
        location = @location
        return "no credentials directory: #{location.searched}" if location.directory.nil?

        return "#{path} not in #{location.file}" if File.file?(location.file)

        environment = location.environment
        return "no credentials for environment #{environment} in #{location.directory}" if environment

        "no #{File.basename(location.file)} in #{location.directory}"
      end

      private

      def load
        return @data if @loaded

        @data = read
        @loaded = true
        @data
      end

      def read
        location = @location
        return if location.directory.nil?
        if location.explicit? && !location.exist?
          raise CredentialsError, "credentials directory not found: #{location.directory}"
        end
        return unless File.file?(location.file)

        plaintext = Box.unseal(File.binread(location.file), location.key!, path: location.file)
        @logger&.debug("credentials: #{location.file}")
        Credentials.load_yaml(plaintext, location.file)
      end

    end
  end
end
