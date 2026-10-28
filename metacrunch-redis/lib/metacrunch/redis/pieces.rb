# frozen_string_literal: true

module Metacrunch
  module Redis
    # Splits what a writer sends into pieces of at most max_bytes, in order;
    # an item larger than that goes alone. The block gives an item's bytes.
    module Pieces

      module_function

      def of(items, max_bytes)
        pieces = []
        piece = []
        bytes = 0
        items.each do |item|
          size = yield(item)
          if !piece.empty? && bytes + size > max_bytes
            pieces << piece
            piece = []
            bytes = 0
          end
          piece << item
          bytes += size
        end
        pieces << piece unless piece.empty?
        pieces
      end

    end
  end
end
