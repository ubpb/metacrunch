# frozen_string_literal: true

require "test_helper"
require "marc"

# Checks ISO 2709 against ruby-marc 1.4, the MARC library most used with Ruby.
class RubyMarcTest < Minitest::Test

  include Fixtures

  Marc = Metacrunch::Marc
  FIXTURES = ["collection", "edge", "prefixed"].freeze

  # The leaders of the fixtures have "a" at 09, "22" at 10-11 and "4500" at
  # 20-23, which ruby-marc copies and the serializer writes.
  def test_writes_what_ruby_marc_writes
    FIXTURES.each do |name|
      Marc::Xml.each(fixture("#{name}.xml")) do |record|
        theirs = MARC::Record.new_from_hash(record.to_h)
        theirs.leader = Marc::Iso2709::Serializer::LEADER.dup unless record.leader

        assert_equal theirs.to_marc.b, record.to_iso2709.b, "#{name}: #{record["001"]&.value}"
      end
    end
  end

  def test_reads_what_ruby_marc_reads
    FIXTURES.each do |name|
      path = fixture_path("#{name}.mrc")
      theirs = MARC::Reader.new(path, external_encoding: "UTF-8").map(&:to_hash)

      assert_equal theirs, Marc::Iso2709.each(File.binread(path)).map(&:to_h), name
    end
  end

end
