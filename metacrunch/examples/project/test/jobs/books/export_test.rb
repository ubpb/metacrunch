# frozen_string_literal: true

# Tests the job books:export with the steps of books:public. project: lets
# the names of use resolve from any working directory.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"
require "tmpdir"

class BooksExportJobTest < Minitest::Test

  def test_names_the_steps_of_the_transform
    Dir.mktmpdir do |out|
      result = Metacrunch::Testing.run(PROJECT, "books:export", params: {output: out})

      assert_equal ["books:public/reject#1", "books:public/map#2"], result.stats.steps.keys
      assert_equal 4, result.records.size
    end
  end

end
