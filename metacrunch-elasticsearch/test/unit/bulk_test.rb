# frozen_string_literal: true

require "test_helper"

class BulkTest < Minitest::Test

  Bulk = Metacrunch::Elasticsearch::Bulk

  def test_lines_of_each_action
    records = [{"id" => "1", "t" => "a"}] * 5
    actions = [:index, :create, :update, :upsert, :delete]
    items, = Bulk.items(records, index: "books", id: "id", action: ->(_) { actions.shift })

    assert_equal [
      %({"index":{"_index":"books","_id":"1"}}\n{"id":"1","t":"a"}\n),
      %({"create":{"_index":"books","_id":"1"}}\n{"id":"1","t":"a"}\n),
      %({"update":{"_index":"books","_id":"1"}}\n{"doc":{"id":"1","t":"a"}}\n),
      %({"update":{"_index":"books","_id":"1"}}\n{"doc":{"id":"1","t":"a"},"doc_as_upsert":true}\n),
      %({"delete":{"_index":"books","_id":"1"}}\n)
    ], items.map(&:lines)
  end

  def test_without_id_elasticsearch_assigns_one
    items, = Bulk.items([{"t" => "a"}], index: "books", id: nil, action: :create)

    assert_equal %({"create":{"_index":"books"}}\n{"t":"a"}\n), items.first.lines
  end

  def test_ids_are_measured_in_bytes
    emoji = [0x1F600].pack("U")
    items, failed = Bulk.items([{"id" => emoji * 128}, {"id" => emoji * 129}], index: "books", id: "id", action: :index)

    assert_equal [[0], [1]], [items.map(&:position), failed.keys]
  end

  def test_an_id_key_finds_string_and_symbol_keys_alike
    by_symbol, = Bulk.items([{"isbn" => "1"}], index: "books", id: :isbn, action: :delete)
    by_string, = Bulk.items([{isbn: "2"}], index: "books", id: "isbn", action: :delete)

    assert_equal ["1", "2"], [by_symbol.first.id, by_string.first.id]
  end

  def test_ids_from_a_callable_and_integers_as_strings
    items, = Bulk.items([{n: 7}], index: "books", id: ->(record) { record[:n] * 2 }, action: :delete)

    assert_equal [14.to_s, %({"delete":{"_index":"books","_id":"14"}}\n)], [items.first.id, items.first.lines]
  end

  def test_records_that_cannot_be_sent_fail_with_their_position
    invalid_utf8 = "\xFF".dup.force_encoding("UTF-8")
    records = [["a"], "a", {"t" => "a"}, {"id" => 1.5}, {"id" => ""}, {"id" => "x" * 513},
               {"id" => "1", "v" => Float::NAN}, {"id" => "1", "v" => invalid_utf8}, {"id" => "ok"}]
    items, failed = Bulk.items(records, index: "books", id: "id", action: ->(r) { r.key?("t") ? :delete : :index })

    assert_equal [8], items.map(&:position)
    assert_equal ["the record is an Array, not a Hash", "the record is a String, not a Hash",
                  "delete needs an id, and the record has none", "the id must be a String or an Integer, got Float",
                  "the id is empty", "the id is longer than 512 bytes"], failed.values_at(*0..5).map(&:message)
    assert_equal [JSON::GeneratorError, JSON::GeneratorError], failed.values_at(6, 7).map(&:class)
  end

  def test_an_action_callable_that_fails_or_answers_nonsense
    _, failed = Bulk.items([{"a" => 1}, {"b" => 2}], index: "books", id: nil,
                                                     action: ->(r) { r.key?("a") ? :replace : raise(KeyError, "kind") })

    assert_equal ["the action must be one of :index, :create, :update, :upsert, :delete, got :replace", "kind"],
                 failed.values.map(&:message)
  end

  def test_requests_of_at_most_max_bytes_and_large_items_alone
    items = [10, 10, 30, 10, 10, 10].each_with_index.map { |size, i| item(i, "x" * size) }

    assert_equal([[0, 1], [2], [3, 4], [5]], Bulk.requests(items, 25).map { it.map(&:position) })
  end

  def test_results_pair_items_with_their_outcome
    items = [item(0, "a"), item(1, "b")]
    response = {"errors" => true, "items" => [{"index" => {"status" => 201}}, {"index" => {"status" => 400}}]}

    assert_equal [[items[0], nil], [items[1], nil]], Bulk.results(items, {"errors" => false})
    assert_equal [[items[0], {"status" => 201}], [items[1], {"status" => 400}]], Bulk.results(items, response)
  end

  def test_what_counts_as_written_and_what_may_pass_later
    assert Bulk.ok?(item(0, "", :delete), {"status" => 404})
    refute Bulk.ok?(item(0, "", :update), {"status" => 404})
    transient = [429, 503, 409].map { Bulk.transient?({"status" => it}) }

    assert_equal [true, true, false], transient
  end

  def test_errors_of_items
    error = Bulk.error(item(3, "", :index, "7"), {"status" => 400, "error" => {"type" => "t", "reason" => "r"}})
    odd = Bulk.error(item(3, "", :index, "7"), {"status" => 500, "error" => "broken"})

    assert_equal ["400 t: r (index 7)", "500 error: broken (index 7)"], [error.message, odd.message]
    assert_equal "413 request_entity_too_large: the document alone is too large (index 7)",
                 Bulk.too_large(item(3, "", :index, "7")).message
  end

  private

  def item(position, lines, action = :index, id = nil) = Bulk::Item.new(position:, action:, id:, lines:)

end
