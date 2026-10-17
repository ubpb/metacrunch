# frozen_string_literal: true

# Tests the transform catalog:public alone and in the job catalog with
# Metacrunch::Testing.run. project: lets the job's names resolve from any
# working directory.
#
#   bundle exec ruby -Ilib examples/project/test/public_test.rb

require "minitest/autorun"
require "tmpdir"
require "metacrunch"
require "metacrunch/testing"

class PublicTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))
  RECORDS = [{"id" => "a", "title" => "A", "public" => true}, {"id" => "b", "title" => "B", "public" => false}].freeze

  def test_keeps_the_public_records_with_the_given_fields
    result = Metacrunch::Testing.run(PROJECT.fetch("catalog:public"), params: {fields: ["id"]}, source: RECORDS)

    assert_equal [{"id" => "a"}], result.records
    assert_equal(["Not public"], result.rejects.map { |_record, rejection| rejection.reason })
  end

  def test_the_job_catalog_names_the_steps_of_the_transform
    Dir.mktmpdir do |out|
      result = Metacrunch::Testing.run(PROJECT.fetch("catalog"), params: {output: out}, project: PROJECT)

      assert_equal ["catalog:public/reject#1", "catalog:public/map#2"], result.stats.steps.keys
      assert_equal 4, result.records.size
    end
  end

end
