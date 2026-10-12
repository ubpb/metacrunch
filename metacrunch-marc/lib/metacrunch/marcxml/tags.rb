# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # The tag of a field is fixed: frozen and deduplicated, so the tag index
    # of a Record stays right and equal tags share one String. Internal.
    module Tags

      module_function

      def fix(tag) = tag.is_a?(String) ? -tag : tag

    end
  end
end
