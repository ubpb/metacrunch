# frozen_string_literal: true

require_relative "diff"
require_relative "trace/renderer"

module Metacrunch
  # Shows what each step does to a few records (metacrunch trace). The
  # engine gets it as observer (step_in, step_out) and #trace? as select:.
  # The events of one source record are collected into a tree and printed
  # when the next record starts or the run ends (#finish), because flat_map
  # children pass the later steps before their flat_map step ends.
  class Trace

    # Snapshot of a record that Marshal cannot copy.
    Opaque = Data.define(:text)
    RecordNode = Struct.new(:position, :id, :steps, :to_sink)
    StepNode = Struct.new(:name, :kind, :input, :outputs, :marks, :rejection, :failure, :children, :marks_before)
    ChildNode = Struct.new(:record, :steps)

    # A sink that discards everything: trace writes nothing.
    class NullSink

      def write(_record) = nil

    end

    def initialize(io, pipeline:, positions: nil, ids: nil, full: false, color: false, width: 160)
      @io = io
      @id_extractor = pipeline.id_extractor
      @kinds = pipeline.steps.to_h { [it.name, it.kind] }.merge(SOURCE_STEP => :source)
      @last_step = pipeline.steps.last&.name
      @positions = positions && Set.new(positions)
      @ids = ids && Set.new(ids.map(&:to_s))
      name_width = [*@kinds.keys, "sink"].map(&:size).max
      @renderer = Renderer.new(full:, color:, width:, name_width:)
      @totals = Hash.new(0)
      @record = nil
    end

    # The select callable: true for every record without positions or ids,
    # otherwise for each listed position or id once. Starts the record.
    def trace?(record, position)
      return false unless wanted?(record, position)

      start_record(record, position)
      true
    end

    def step_in(step, record, ctx)
      node = StepNode.new(name: step, kind: @kinds.fetch(step), input: snapshot(record), outputs: [], marks: [],
                          children: [], marks_before: ctx.marks.size)
      (@lists[ctx] ||= new_list(record)) << node
      @current[ctx] = node
      @open.push(node) if node.kind == :flat_map
    end

    def step_out(step, outputs, ctx)
      node = @current.delete(ctx)
      node.outputs = outputs.map { snapshot(it) }
      if node.kind == :flat_map
        @open.pop
        # Children that passed no later step (flat_map is the last step).
        node.children.concat(node.outputs.drop(node.children.size).map { ChildNode.new(record: it, steps: []) })
      end
      node.marks = ctx.marks.drop(node.marks_before)
      node.rejection = ctx.rejection if ctx.rejection&.step == step
      node.failure = ctx.failure if ctx.failure&.step == step
      count(node)
    end

    # Prints the last record and the summary. Call after the run.
    def finish
      flush_record
      @io.puts(@renderer.summary(@totals))
    end

    private

    def wanted?(record, position)
      return !@positions.delete?(position).nil? if @positions
      return true unless @ids

      id = record_id(record)
      !id.nil? && !@ids.delete?(id.to_s).nil?
    end

    def record_id(record)
      return if record.is_a?(InvalidRecord) || @id_extractor.nil?

      @id_extractor.call(record)
    end

    def start_record(record, position)
      flush_record
      direct = @last_step.nil? && !record.is_a?(InvalidRecord) ? 1 : 0
      @record = RecordNode.new(position:, id: record_id(record), steps: [], to_sink: direct)
      @lists = {}.compare_by_identity
      @current = {}.compare_by_identity
      @open = []
      @totals[:records] += 1
    end

    def flush_record
      return unless @record

      @totals[:to_sink] += @record.to_sink
      @io.puts(@renderer.record(@record))
      @record = nil
    end

    # The step list for a context seen for the first time: the record's own
    # list, or a new child of the innermost open flat_map.
    def new_list(record)
      parent = @open.last
      return @record.steps unless parent

      child = ChildNode.new(record: snapshot(record), steps: [])
      parent.children << child
      child.steps
    end

    def count(node)
      if node.failure
        @totals[:failed] += 1
      elsif node.rejection
        @totals[:rejected] += 1
      elsif node.outputs.empty? && [:filter, :reject].include?(node.kind)
        @totals[:filtered] += 1
      end
      @record.to_sink += node.outputs.size if node.name == @last_step
    end

    # Steps may change records in place, so inputs and outputs are copied
    # when the event happens.
    def snapshot(record)
      Marshal.load(Marshal.dump(record))
    rescue TypeError
      Opaque.new(text: record.inspect)
    end

  end
end
