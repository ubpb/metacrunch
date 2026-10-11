# frozen_string_literal: true

module Metacrunch
  # Compares two Hash records for trace. Nested Hashes are compared key by
  # key with a dotted path ("meta.source"); other values, including Arrays,
  # as a whole.
  module Diff

    # kind: :removed, :added or :changed. before or after is nil when the
    # key is missing on that side.
    Change = Data.define(:kind, :path, :before, :after)

    ORDER = {removed: 0, added: 1, changed: 2}.freeze

    module_function

    # The changes from before to after: removed keys first, then added, then
    # changed ones, each in key order.
    def changes(before, after)
      collect(before, after, nil).sort_by.with_index { |change, index| [ORDER.fetch(change.kind), index] }
    end

    def collect(before, after, prefix)
      (before.keys | after.keys).flat_map do |key|
        compare(before, after, key, prefix ? "#{prefix}.#{key}" : key.to_s)
      end
    end

    def compare(before, after, key, path)
      return [Change.new(kind: :added, path:, before: nil, after: after[key])] unless before.key?(key)
      return [Change.new(kind: :removed, path:, before: before[key], after: nil)] unless after.key?(key)

      old_value = before[key]
      new_value = after[key]
      return collect(old_value, new_value, path) if old_value.is_a?(Hash) && new_value.is_a?(Hash)
      return [] if old_value == new_value

      [Change.new(kind: :changed, path:, before: old_value, after: new_value)]
    end

  end
end
