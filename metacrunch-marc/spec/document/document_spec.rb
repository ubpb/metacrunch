describe Metacrunch::Mab2::Document do

  describe "#from_aleph_mab_xml" do
    let(:xml) { default_test_xml }
    let(:document) { Metacrunch::Mab2::Document.from_aleph_mab_xml(xml) }
    subject { document }

    it "should create a Document from Aleph MAB XML" do
      expect(subject).to be_instance_of(Metacrunch::Mab2::Document)
    end
  end

  describe ".add_control_field" do
    let(:document) { empty_document }

    it "should add control fields" do
      document.add_control_field(create_control_field("001", "a|a|"))
      expect(document.control_field("001").values).to eq(["a", nil, "a", nil])
    end
  end

  describe ".control_fields" do
    let(:document) { default_test_document }
    subject { document.all_control_fields }

    it { is_expected.to be_instance_of(Array) }
    it { is_expected.not_to be_empty }
    it "should return all control fields" do
      expect(subject.count).to be(3)
    end
  end

  describe ".control_field" do
    let(:document) { default_test_document }
    subject { document.control_field("050") }

    it { is_expected.not_to be_nil }
    it { is_expected.to be_instance_of(Metacrunch::Mab2::Document::ControlField) }
    it "should contain the correct values" do
      expect(subject.values).to eq(["a", nil, "a", nil])
    end
  end

private

  def empty_document
    Metacrunch::Mab2::Document.new
  end

  def default_test_document
    document = Metacrunch::Mab2::Document.new
    document.add_control_field(create_control_field("LDR", "01234"))
    document.add_control_field(create_control_field("050", "a|a|"))
    document.add_control_field(create_control_field("052", ["a", nil, "b"]))
    document
  end

  def default_test_xml
    File.read(File.join(RSpec.root, "assets", "aleph_mab_xml", "file1.xml"))
  end

  def create_control_field(name, values)
    Metacrunch::Mab2::Document::ControlField.new(name, values)
  end

end
