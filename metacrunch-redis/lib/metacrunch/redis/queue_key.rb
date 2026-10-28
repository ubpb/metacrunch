# frozen_string_literal: true

module Metacrunch
  module Redis
    # The key of a queue, shared by its reader and writer.
    module QueueKey

      module_function

      def check_name!(value) = Options.string(value, :queue)

      # Raises Error unless the key holds a list or nothing.
      def check_type!(client, key)
        type = client.call("TYPE", key)
        return if ["list", "none"].include?(type)

        raise Error, "#{key} holds a #{type}, not a list"
      end

    end
  end
end
