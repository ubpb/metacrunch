# frozen_string_literal: true

require "test_helper"
require "timeout"

# Workbooks with mutated parts in a sound ZIP archive: whatever a buggy
# writer produces, the reader yields records or invalid records, or raises
# InputError, and ends.
class ReaderFuzzTest < Minitest::Test

  RUNS = 2000
  CHARACTERS = ["<", ">", "/", "\"", "'", "&", "=", ";", "#", "x", "_x", "0", "9", "-", ".", "E", " ", "\n"].freeze

  def test_mutated_workbooks_give_records_or_input_errors
    random = Random.new(42)
    outcomes = Hash.new(0)
    RUNS.times do |run|
      name, parts = mutate(random)
      records = Timeout.timeout(2) { read(parts) }
      bad = records.reject { it.is_a?(Hash) || it.is_a?(Metacrunch::InvalidRecord) }
      flunk("#{name}, mutation #{run}: #{bad.first.inspect}") unless bad.empty?
      outcomes[records.any?(Metacrunch::InvalidRecord) ? :invalid : :records] += 1
    rescue Metacrunch::InputError
      outcomes[:errors] += 1
    rescue Minitest::Assertion
      raise
    rescue Exception => e # rubocop:disable Lint/RescueException
      flunk("#{name}, mutation #{run}: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
    end

    # Every outcome occurs, so the mutations reach the reader: records and
    # errors in more than a tenth of the runs, invalid records in more than
    # a hundredth.
    assert_operator [outcomes[:records], outcomes[:errors], outcomes[:invalid] * 10].min, :>, RUNS / 10,
                    outcomes.inspect
  end

  private

  def seed
    @seed ||= begin
      sheet = [%(<row r="1" spans="1:5"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c>),
               %(<c r="C1" t="inlineStr"><is><t>date</t></is></c><c r="D1" t="str"><v>flag</v></c></row>),
               %(<row r="2"><c r="A2"><v>1</v></c><c r="B2" t="s"><v>2</v></c><c r="C2" s="1"><v>45597.5</v></c>),
               %(<c r="D2" t="b"><v>1</v></c></row>),
               %(<row r="3"><c r="A3"><v>2.5</v></c><c r="B3" t="e"><v>#N/A</v></c><c r="C3" s="2"><v>45597</v></c>),
               %(<c r="D3" t="d"><v>2024-11-01T00:00:00</v></c></row>)].join
      WorkbookBuilder.parts(sheets: {"Sheet1" => sheet},
                            strings: ["<t>id</t>", "<t>title</t>", "<r><t>Mo</t></r><r><t>by &amp; _x000D_</t></r>"],
                            xfs: [0, 164, 14], formats: {164 => "[$-409]yyyy-mm-dd h:mm AM/PM;@"},
                            date1904: false, types: WorkbookBuilder::RELATIONSHIPS)
    end
  end

  def read(parts) = Metacrunch::Xlsx::Reader.new(StringIO.new(WorkbookBuilder.zip(parts))).each.to_a

  # One part changed: a byte flipped or set, a cut, a tag repeated, a
  # range deleted, or a character of XML or of a number inserted.
  def mutate(random)
    name = seed.keys.sample(random:)
    xml = seed[name].b
    at = random.rand(xml.bytesize)
    case random.rand(100)
    when 0...20 then xml.setbyte(at, xml.getbyte(at) ^ (1 << random.rand(8)))
    when 20...30 then xml = xml.byteslice(0, at)
    when 30...50
      tag = xml.byteslice(at..)[/<[^<>]*>/]
      xml.insert(random.rand(xml.bytesize), tag.to_s)
    when 50...65 then xml[at, 1 + random.rand(12)] = ""
    else xml.insert(at, CHARACTERS.sample(random:))
    end
    [name, seed.merge(name => xml)]
  end

end
