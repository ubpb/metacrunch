# frozen_string_literal: true

# Tests the job books:ids, which uses books:public with other fields.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"

class BooksIdsJobTest < Minitest::Test

  def test_keeps_the_ids_of_the_public_titles
    result = Metacrunch::Testing.run(PROJECT, "books:ids")

    assert_equal [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t4"}, {"id" => "t5"}], result.records
  end

end
