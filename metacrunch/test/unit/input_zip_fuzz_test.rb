# frozen_string_literal: true

require "test_helper"
require "timeout"

# Mutated ZIP archives: whatever a broken download or a buggy writer
# produces, Input yields documents or raises InputError, and ends.
class InputZipFuzzTest < Minitest::Test

  RUNS = 400
  FIXTURES = File.expand_path("../fixtures/zip", __dir__)

  def test_mutated_archives_give_documents_or_input_errors
    random = Random.new(42)
    outcomes = Hash.new(0)
    seeds.each do |seed, archive|
      (RUNS / seeds.size).times do |run|
        bytes = mutate(archive, random)
        Timeout.timeout(2) { read(bytes) }
        outcomes[:documents] += 1
      rescue Metacrunch::InputError
        outcomes[:errors] += 1
      rescue Exception => e # rubocop:disable Lint/RescueException
        flunk("#{seed}, mutation #{run}: #{e.class}: #{e.message}")
      end
    end

    # Both outcomes occur, so the mutations reach the reader.
    assert_operator outcomes[:documents], :>, RUNS / 10
    assert_operator outcomes[:errors], :>, RUNS / 10
  end

  private

  def seeds
    @seeds ||= {
      "builder (Zip64, comment)" => ZipBuilder.build(
        [{name: "a.csv", data: "id,title\n1,a\n" * 50, zip64: true}, {name: "d/", method: 0}],
        zip64: true, comment: "comment"
      ),
      "builder (descriptor)" => ZipBuilder.build([{name: "a.txt", data: "a" * 3000, descriptor: :signed},
                                                  {name: "b.txt", data: "b", method: 0}]),
      **["winxp.zip", "zip64.zip", "utf8-osx.zip", "dd.zip"].to_h { [it, File.binread(File.join(FIXTURES, it))] }
    }
  end

  def read(bytes)
    Metacrunch::Input.new(StringIO.new(bytes), unpack: Metacrunch::Input::UNPACK).each_document { |stream, _name| stream.read }
  end

  # Flips a bit or sets a byte near the end (end records, directory), sets
  # a field to 0xFF (Zip64 paths), changes a byte anywhere, cuts the end,
  # or inserts or deletes bytes.
  def mutate(bytes, random)
    bytes = bytes.b
    tail = [bytes.bytesize, 600].min
    case random.rand(100)
    when 0...40
      at = bytes.bytesize - 1 - random.rand(tail)
      bytes.setbyte(at, bytes.getbyte(at) ^ (1 << random.rand(8)))
    when 40...60 then bytes.setbyte(random.rand(bytes.bytesize), random.rand(256))
    when 60...80
      at = bytes.bytesize - 1 - random.rand(tail)
      width = [2, 4, 8].sample(random:)
      bytes[at, width] = "\xFF".b * [width, bytes.bytesize - at].min
    when 80...90 then bytes = bytes.byteslice(0, random.rand(bytes.bytesize))
    else
      at = random.rand(bytes.bytesize)
      random.rand(2).zero? ? bytes.insert(at, random.bytes(1 + random.rand(3))) : bytes[at, 1 + random.rand(3)] = ""
    end
    bytes
  end

end
