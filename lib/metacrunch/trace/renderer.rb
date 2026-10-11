# frozen_string_literal: true

require "json"

module Metacrunch
  class Trace
    # Turns the collected steps of one record into lines of text: a diff
    # per step for Hash records, inspect-like values otherwise.
    class Renderer

      INDENT = "  "
      COLORS = {header: 1, dim: 2, removed: 31, failed: 31, added: 32, changed: 33, note: 36}.freeze
      # Backtrace lines in here are metacrunch's own, not the job's.
      LIB = "#{File.expand_path("../..", __dir__)}/".freeze

      def initialize(full:, color:, width:, name_width:)
        @full = full
        @color = color
        @name_width = name_width
        @value_width = [width - name_width - 12, 20].max
      end

      # The lines of one traced record.
      def record(node)
        header = node.id.nil? ? "##{node.position}" : "##{node.position}  id=#{node.id}"
        lines = [paint(:header, header)]
        node.steps.each { step(it, 1, lines) }
        lines << row(1, "sink", "#{count(node.to_sink, "record")} (not written)") if node.to_sink.positive?
        lines.join("\n")
      end

      def summary(totals)
        parts = ["#{totals[:to_sink]} to sink"]
        [:filtered, :rejected, :failed].each { |key| parts << "#{totals[key]} #{key}" if totals[key].positive? }
        "traced #{count(totals[:records], "record")}: #{parts.join(", ")}"
      end

      private

      def step(node, depth, lines)
        texts = effect(node) + node.marks.map { paint(:note, "mark: #{mark(it)}") }
        lines << row(depth, node.name, texts.first)
        texts.drop(1).each { lines << row(depth, "", it) }
        node.children.each_with_index { |child, index| child_lines(child, index + 1, node.input, depth + 1, lines) }
      end

      def child_lines(child, number, parent_input, depth, lines)
        texts = @full ? [show(child.record)] : changes(parent_input, child.record)
        lines << row(depth, "[#{number}]", texts.first)
        texts.drop(1).each { lines << row(depth, "", it) }
        child.steps.each { step(it, depth + 1, lines) }
      end

      def effect(node)
        return failure(node) if node.failure
        return [paint(:failed, "rejected: #{node.rejection.reason}")] if node.rejection

        case node.kind
        when :flat_map then ["→ #{count(node.outputs.size, "record")}"]
        when :map then @full ? full(node) : changes(node.input, node.outputs.first)
        else @full ? full(node) : [kept(node)]
        end
      end

      # The effect of a filter or reject step that dropped nothing silently.
      def kept(node)
        node.outputs.empty? ? "filtered" : paint(:dim, "pass")
      end

      def failure(node)
        error = node.failure.error
        text = "failed: #{error.class}: #{error.message.lines.first&.chomp}"
        location = node.kind == :source ? nil : location(error)
        lines = [paint(:failed, location ? "#{text}  (#{location})" : text)]
        lines << "raw: #{show(node.input)}" if node.kind == :source
        lines
      end

      def full(node)
        outputs = node.outputs.map { "out: #{show(it)}" }
        ["in:  #{show(node.input)}", *(outputs.empty? ? ["out: (none)"] : outputs)]
      end

      def changes(before, after)
        return [paint(:dim, "unchanged")] if before == after
        return ["#{show(before)} → #{show(after)}"] unless before.is_a?(Hash) && after.is_a?(Hash)

        Diff.changes(before, after).map { change(it) }
      end

      def change(change)
        path = JSON.generate(change.path)
        case change.kind
        when :removed then paint(:removed, "- #{path}: #{show(change.before)}")
        when :added then paint(:added, "+ #{path}: #{show(change.after)}")
        else paint(:changed, "~ #{path}: #{show(change.before)} → #{show(change.after)}")
        end
      end

      def mark(mark)
        mark.value.nil? ? mark.reason : "#{mark.reason} (#{show(mark.value)})"
      end

      def show(value)
        text = value.is_a?(Opaque) ? value.text : json(value)
        @full || text.size <= @value_width ? text : "#{text[0, @value_width - 1]}…"
      end

      def json(value)
        JSON.generate(value, strict: true)
      rescue JSON::GeneratorError
        value.inspect
      end

      # The first backtrace line outside metacrunch, relative to the working
      # directory, without the method name.
      def location(error)
        line = error.backtrace&.find { !it.start_with?(LIB, "<internal:") }
        line&.delete_prefix("#{Dir.pwd}/")&.sub(/:in .*\z/, "")
      end

      def row(depth, label, text)
        "#{INDENT * depth}#{label.ljust(@name_width)}  #{text}".rstrip
      end

      def count(number, word) = "#{number} #{word}#{"s" unless number == 1}"

      def paint(style, text)
        @color ? "\e[#{COLORS.fetch(style)}m#{text}\e[0m" : text
      end

    end
  end
end
