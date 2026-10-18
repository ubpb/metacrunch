# frozen_string_literal: true

# Tests the job catalog with the steps of catalog:public. project: lets
# the names of use resolve from any working directory.
#
#   cd examples/project && bundle exec rake

require_relative "../test_helper"
require "tmpdir"

class CatalogJobTest < Minitest::Test

  def test_names_the_steps_of_the_transform
    Dir.mktmpdir do |out|
      result = Metacrunch::Testing.run(PROJECT.fetch("catalog"), params: {output: out}, project: PROJECT)

      assert_equal ["catalog:public/reject#1", "catalog:public/map#2"], result.stats.steps.keys
      assert_equal 4, result.records.size
    end
  end

end
