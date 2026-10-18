# frozen_string_literal: true

# Tests the job catalog:ids, which uses catalog:public with other fields.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"

class CatalogIdsJobTest < Minitest::Test

  def test_keeps_the_ids_of_the_public_titles
    result = Metacrunch::Testing.run(PROJECT.fetch("catalog:ids"), project: PROJECT)

    assert_equal [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t4"}, {"id" => "t5"}], result.records
  end

end
