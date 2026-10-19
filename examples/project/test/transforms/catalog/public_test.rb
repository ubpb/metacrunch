# frozen_string_literal: true

# Tests the transform catalog:public alone with Metacrunch::Testing.run.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"

class CatalogPublicTransformTest < Minitest::Test

  RECORDS = [{"id" => "a", "title" => "A", "public" => true}, {"id" => "b", "title" => "B", "public" => false}].freeze

  def test_keeps_the_public_records_with_the_given_fields
    result = Metacrunch::Testing.run(PROJECT, "catalog:public", params: {fields: ["id"]}, source: RECORDS)

    assert_equal [{"id" => "a"}], result.records
    assert_equal(["Not public"], result.rejects.map { |_record, rejection| rejection.reason })
  end

end
