require_relative "../transformer"

module Metacrunch
  class Transformer
    class Step

      def initialize(transformer)
        @transformer = transformer
      end

      def perform
        raise NotImplementedError, "You must implement .perform() in your rule sub-class"
      end

      def transformer
        @transformer
      end

      def source
        transformer.source
      end

      def target
        transformer.target
      end

      def options
        transformer.options
      end

      def helper
        transformer.helper
      end

    end
  end
end
