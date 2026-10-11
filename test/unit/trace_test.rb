# frozen_string_literal: true

require "test_helper"
require "metacrunch/trace"

class TraceTest < Minitest::Test

  include PipelineHelper

  # A record Marshal cannot copy.
  class Unmarshalable

    def initialize
      @callback = proc {}
    end

    def inspect = "#<Unmarshalable>"

  end

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

  end

  def test_a_closed_pipe_ends_the_trace_like_sigpipe
    pipeline = build_pipeline { source [1] }
    trace = Metacrunch::Trace.new(ClosedPipe.new, pipeline:)
    error = assert_raises(SignalException) { trace.finish }

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_shows_the_effect_of_each_step
    output = trace_run do
      source [{"_id" => 1, "public" => true}, {"_id" => 2, "public" => false}], id: ->(record) { record["_id"] }
      reject("Not public") { !it["public"] }
      filter { it["_id"] < 10 }
      map { |record| {"id" => record["_id"]} }
    end

    assert_equal <<~TEXT, output
      #1  id=1
        reject#1  pass
        filter#2  pass
        map#3     - "_id": 1
                  - "public": true
                  + "id": 1
        sink      1 record (not written)
      #2  id=2
        reject#1  rejected: Not public
      traced 2 records: 1 to sink, 1 rejected
    TEXT
  end

  def test_shows_flat_map_children_and_their_way_through_later_steps
    output = trace_run do
      source [{"id" => 17, "isbns" => ["a", "b"]}]
      flat_map do |record|
        isbns = record.delete("isbns")
        isbns.map { |isbn| record.merge("isbn" => isbn) }
      end
      map { |record| record["isbn"] == "b" ? raise(KeyError, "no b") : record.merge("ok" => true) }
      on_error :skip
    end

    assert_equal <<~TEXT, output.sub(%r{  \(test/unit/trace_test\.rb:\d+\)}, "  (LOCATION)")
      #1
        flat_map#1  → 2 records
          [1]         - "isbns": ["a","b"]
                      + "isbn": "a"
            map#2       + "ok": true
          [2]         - "isbns": ["a","b"]
                      + "isbn": "b"
            map#2       failed: KeyError: no b  (LOCATION)
        sink        1 record (not written)
      traced 1 record: 1 to sink, 1 failed
    TEXT
  end

  def test_shows_other_records_in_full
    output = trace_run do
      source [1, 2]
      map { it * 10 }
      filter { it > 10 }
      map { it }
    end

    assert_equal <<~TEXT, output
      #1
        map#1     1 → 10
        filter#2  filtered
      #2
        map#1     2 → 20
        filter#2  pass
        map#3     unchanged
        sink      1 record (not written)
      traced 2 records: 1 to sink, 1 filtered
    TEXT
  end

  def test_shows_marks
    output = trace_run do
      source [{"id" => 1}]
      map do |record, ctx|
        ctx.mark("No title", value: 3)
        record
      end
    end

    assert_equal <<~TEXT, output
      #1
        map#1   unchanged
                mark: No title (3)
        sink    1 record (not written)
      traced 1 record: 1 to sink
    TEXT
  end

  def test_shows_invalid_records
    bad = Metacrunch::InvalidRecord.new(raw: "{oops", error: JSON::ParserError.new("unexpected token"))
    output = trace_run do
      source [bad]
      map { it }
      on_error :skip
    end

    assert_equal <<~TEXT, output
      #1
        source  failed: JSON::ParserError: unexpected token
                raw: "{oops"
      traced 1 record: 0 to sink, 1 failed
    TEXT
  end

  def test_full_shows_whole_records
    output = trace_run(full: true) do
      source [{"a" => 1}]
      map { it.merge("b" => 2) }
    end

    assert_equal <<~TEXT, output
      #1
        map#1   in:  {"a":1}
                out: {"a":1,"b":2}
        sink    1 record (not written)
      traced 1 record: 1 to sink
    TEXT
  end

  def test_traces_selected_positions_and_ids_once
    by_position = trace_run(positions: [2, 4]) do
      source ["a", "b", "c", "d"]
      map(&:upcase)
    end
    by_id = trace_run(ids: ["2"]) do
      source [{"id" => 1}, {"id" => 2}, {"id" => 2}], id: ->(record) { record["id"] }
    end

    assert_equal ["#2\n", "#4\n"], by_position.lines.grep(/\A#/)
    assert_includes by_position, "  map#1   \"b\" → \"B\"\n"
    assert_equal ["#2  id=2\n"], by_id.lines.grep(/\A#/)
  end

  def test_records_that_cannot_be_copied_are_shown_by_inspect
    record = Unmarshalable.new
    output = trace_run do
      source [record]
      map { "done" }
    end

    assert_includes output, "  map#1   #<Unmarshalable> → \"done\"\n"
  end

  def test_long_values_are_shortened_unless_full
    output = trace_run(width: 40) do
      source [{"text" => "x" * 50}]
      map { it.merge("text" => "y") }
    end

    assert_includes output, "~ \"text\": \"#{"x" * 20}… → \"y\""
  end

  def test_colors
    output = trace_run(color: true) do
      source [{"a" => 1}]
      map { it.merge("id" => 1) }
    end

    assert_includes output, "\e[1m#1\e[0m"
    assert_includes output, "\e[32m+ \"id\": 1\e[0m"
  end

  def test_a_job_without_steps
    assert_equal("#1\n  sink    1 record (not written)\ntraced 1 record: 1 to sink\n", trace_run { source [1] })
  end

  private

  def trace_run(positions: nil, ids: nil, full: false, color: false, width: 160, &)
    pipeline = build_pipeline(&)
    io = StringIO.new
    trace = Metacrunch::Trace.new(io, pipeline:, positions:, ids:, full:, color:, width:)
    Metacrunch::Engine.new(pipeline, observer: trace, select: trace.method(:trace?)).run
    trace.finish
    io.string
  end

end
