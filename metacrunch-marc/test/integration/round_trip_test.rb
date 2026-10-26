# frozen_string_literal: true

require "test_helper"

# Every fixture through every pair of input and output format.
class RoundTripTest < Minitest::Test

  include Fixtures

  Marc = Metacrunch::Marc
  FORMATS = [:xml, :iso2709, :json].freeze
  EXTENSIONS = {xml: "xml", iso2709: "mrc", json: "jsonl"}.freeze
  # local.xml has a tag and codes that ISO 2709 cannot hold.
  FIXTURES = {"collection" => FORMATS, "edge" => FORMATS, "prefixed" => FORMATS, "local" => [:xml, :json]}.freeze
  # The leader positions the ISO 2709 serializer computes.
  COMPUTED = [[0, 5], [9, 1], [10, 2], [12, 5], [20, 3]].freeze

  def test_every_fixture_through_every_pair_of_formats
    FIXTURES.each do |name, formats|
      originals = Marc::Xml.each(fixture("#{name}.xml")).to_a
      formats.product(formats).each do |input, output|
        back = read(write(read(File.binread(fixture_path("#{name}.#{EXTENSIONS[input]}")), input), output), output)
        iso = [input, output].include?(:iso2709)
        message = "#{name}: #{input} to #{output}"

        assert_equal originals.map(&:fields), back.map(&:fields), message
        assert_equal(originals.map { leader(it.leader, iso) }, back.map { leader(it.leader, iso) }, message)
        assert_equal(originals.map { input == :xml && output == :xml ? it.type : nil }, back.map(&:type), message)
      end
    end
  end

  private

  def read(string, format) = Marc::Formats.library(format).each(string).to_a

  def write(records, format)
    case format
    when :xml then Marc::Xml::HEADER + records.map { it.to_xml(namespace: false) }.join + Marc::Xml::FOOTER
    when :iso2709 then records.map(&:to_iso2709).join
    else records.map { Marc::Json::Serializer.record(it) }.join
    end
  end

  # With ISO 2709 on the way, a leader without the computed positions (a
  # record without a leader gets one).
  def leader(leader, iso)
    return leader unless iso

    masked = (leader || Marc::Iso2709::Serializer::LEADER).dup
    COMPUTED.each { |start, length| masked[start, length] = "#" * length }
    masked
  end

end
