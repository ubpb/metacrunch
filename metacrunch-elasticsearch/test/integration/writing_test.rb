# frozen_string_literal: true

require "test_helper"

class WritingTest < Minitest::Test

  include Integration

  Writer = Metacrunch::Elasticsearch::Writer

  def setup
    super
    create_index
    index_documents([{"id" => "1", "title" => "Moby Dick", "year" => 1851}])
  end

  def test_every_action
    records = [{"id" => "2", "do" => "index", "year" => 1813}, {"id" => "1", "do" => "create"},
               {"id" => "9", "do" => "update", "year" => 2000}, {"id" => "1", "do" => "update", "year" => 1852},
               {"id" => "3", "do" => "upsert", "year" => 1847}, {"id" => "8", "do" => "delete"}]
    error = assert_raises(Metacrunch::SinkFailures) do
      open_writer(id: "id", action: -> { it["do"].to_sym }).write_batch(records)
    end

    assert_equal({1 => 409, 2 => 404}, error.failed.transform_values(&:status))
    assert_equal({"1" => 1852, "2" => 1813, "3" => 1847}, stored.transform_values { it["year"] })
  end

  def test_a_value_the_mapping_refuses_fails_with_elasticsearch_s_reason
    error = assert_raises(Metacrunch::SinkFailures) do
      open_writer(id: "id").write_batch([{"id" => "2", "year" => "unknown"}, {"id" => "3", "year" => 1900}])
    end
    failure = error.failed.fetch(0)

    assert_equal [400, :index, "2"], [failure.status, failure.action, failure.id]
    assert_match "[year]", failure.reason
  end

  def test_deletes_and_writes_without_id
    open_writer(action: :create).write_batch([{"title" => "Emma"}])
    open_writer(id: "id", action: :delete).write_batch([{"id" => "1"}])

    assert_equal [["Emma"]], [stored.values.map { it["title"] }]
  end

  def test_requests_of_at_most_max_bytes
    open_writer(id: "id", max_bytes: 200).write_batch((10..19).map { {"id" => it.to_s, "year" => 1900 + it} })

    assert_equal 11, stored.size
  end

  def test_writes_through_an_alias
    client.indices.put_alias(index: @index, name: "#{@index}-alias")
    open_writer(index: "#{@index}-alias", id: "id").write_batch([{"id" => "5", "year" => 1900}])

    assert_includes stored.keys, "5"
  end

  def test_open_refuses_an_alias_of_two_indices_without_a_write_index
    other = create_index("#{@index}-other")
    client.indices.update_aliases(body: {actions: [{add: {index: @index, alias: "#{@index}-both"}},
                                                   {add: {index: other, alias: "#{@index}-both"}}]})
    error = assert_raises(Metacrunch::OutputError) { open_writer(index: "#{@index}-both") }

    assert_match "and to none of them as its write index", error.message
  end

  def test_open_refuses_a_missing_index
    error = assert_raises(Metacrunch::OutputError) { open_writer(index: "#{@index}-missing") }

    assert_equal "elasticsearch #{@index}-missing: no such index or alias", error.message
  end

  private

  def open_writer(index: @index, **) = Writer.new(connection, index:, **).tap { it.open(context) }

end
