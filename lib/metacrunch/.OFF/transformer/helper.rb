require_relative "../transformer"

module Metacrunch
  class Transformer
    class Helper

      def initialize(transformer)
        @transformer = transformer
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

    end
  end
end
