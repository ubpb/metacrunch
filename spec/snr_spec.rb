describe Metacrunch::SNR do

  let(:snr) { Metacrunch::SNR.new }


  describe ".add" do
    it "adds a field and creates a section if the section doesn't exists" do
      expect {
        snr.add("mysection", "myfield", "My Value")
      }.to change { snr.sections.count }.by(1)
    end

    it "adds a field to an existsing section" do
      snr.add_section(Metacrunch::SNR::Section.new("mysection"))

      expect {
        snr.add("mysection", "myfield", "My Value")
      }.not_to change { snr.sections.count }
    end
  end

  describe ".sections" do
    let(:section1) { Metacrunch::SNR::Section.new("section1") }
    let(:section2) { Metacrunch::SNR::Section.new("section2") }

    before {
      snr.add_section(section1)
      snr.add_section(section2)
    }

    subject { snr.sections }

    it "returns all sections" do
      expect(snr.sections.count).to be(2)
    end

    it { is_expected.not_to be_empty }
    it { is_expected.to include(section1) }
    it { is_expected.to include(section2) }
  end

  describe ".section(name)" do
    context "when section exists" do
      let(:section1) { Metacrunch::SNR::Section.new("section1") }
      before { snr.add_section(section1) }
      subject { snr.section("section1") }

      it { is_expected.not_to be_nil }
      it { is_expected.to be(section1) }
    end

    context "when section doesn't exists" do
      subject { snr.section("no_such_section") }

      it { is_expected.to be_nil }
    end
  end

  describe ".to_xml" do
    before {
      snr.add("section1", "title", "Foo Bar")
      snr.add("section1", "artist", ["Sievers, Michael", "Sprotte, René"])
      snr.add("section2", "link", {label: "Click here", url: "http://example.com"})
    }

    subject { snr.to_xml }

    it { is_expected.not_to be_nil }
    it { is_expected.not_to be_empty }
    it { is_expected.to eq("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<snr>\n  <section1>\n    <title>Foo Bar</title>\n    <artist>Sievers, Michael</artist>\n    <artist>Sprotte, René</artist>\n  </section1>\n  <section2>\n    <link type=\"array\">\n      <link type=\"symbol\">label</link>\n      <link>Click here</link>\n    </link>\n    <link type=\"array\">\n      <link type=\"symbol\">url</link>\n      <link>http://example.com</link>\n    </link>\n  </section2>\n</snr>\n") }
  end

end
