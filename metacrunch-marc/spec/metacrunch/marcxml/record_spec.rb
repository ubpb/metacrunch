describe Metacrunch::Marcxml::Record do

  # -----------------------------------------------------------------------
  # Empty
  # -----------------------------------------------------------------------

  describe "#empty" do
    subject {
      Metacrunch::Marcxml.parse <<-XML
        <record>
        </record>
      XML
    }
    it { is_expected.to be_nil }
  end

  # -----------------------------------------------------------------------
  # Leader
  # -----------------------------------------------------------------------

  describe "#leader" do
    let(:record_with_leader) {
      Metacrunch::Marcxml.parse <<-XML
        <record>
          <leader>123456</leader>
          <controlfield tag="001">XXXX</controlfield>
        </record>
      XML
    }

    let(:record_without_leader) {
      Metacrunch::Marcxml.parse <<-XML
        <record>
          <controlfield tag="001">XXXX</controlfield>
        </record>
      XML
    }

    context "record with leader" do
      subject { record_with_leader.leader.value }
      it { is_expected.to eq("123456") }
    end

    context "record without leader" do
      subject { record_without_leader.leader }
      it { is_expected.to be_nil }
    end
  end

  # -----------------------------------------------------------------------
  # Controlfields
  # -----------------------------------------------------------------------

  describe "#controlfield" do
    let(:record) { default_test_record }

    context "given nil tag" do
      subject { record.controlfield(nil) }

      it { is_expected.to be_nil }
    end

    context "given non-existing tag" do
      subject { record.controlfield("666") }

      it { is_expected.to be_nil }
    end

    context "given existing tag" do
      subject { record.controlfield("050") }

      it { is_expected.not_to be_nil }
      it { is_expected.to be_instance_of(Metacrunch::Marcxml::Record::Controlfield) }
      it "should contain the correct values" do
        expect(subject.value).to eq("a|a|")
      end
    end
  end

  describe "#add_controlfield" do
    let(:record) { empty_record }

    it "should add control field" do
      record.add_controlfield(create_controlfield("001", "a|a|"))
      expect(record.controlfield("001").value).to eq("a|a|")
    end
  end

  # -----------------------------------------------------------------------
  # Datafields
  # -----------------------------------------------------------------------

  describe "#datafields" do
    let(:record) { default_test_record }

    context "given tag=nil" do
      subject { record.datafields(nil) }

      it "returns a DatafieldSet" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Record::DatafieldSet)
      end

      it "DatafieldSet contains all datafields" do
        expect(subject.count).to eq(record.instance_variable_get("@datafields_map").values.flatten(1).count)
      end
    end

    context "given non existing tag" do
      subject { record.datafields("_not_existing_tag_") }

      it "returns a DatafieldSet" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Record::DatafieldSet)
      end

      it "DatafieldSet is empty" do
        expect(subject.empty?).to be(true)
      end
    end

    context "given tag=100" do
      subject { record.datafields("100") }

      it "returns only datafields with tag=100" do
        expect(subject.all?{|f| f.tag=="100"}).to be(true)
      end
    end

    context "given tag=100 and tag=331" do
      subject { record.datafields(["100", "331"]) }

      it "returns only datafields with tag=100 or tag=331" do
        expect(subject.all?{|f| f.tag=="100" || f.tag=="331"}).to be(true)
      end
    end

    context "given tag=100 and ind1=-" do
      subject { record.datafields("100", ind1: "-") }

      it "returns only datafields with tag=100 and ind1=-" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1=="-"}).to be(true)
      end
    end

    context "given tag=100 and ind2=2" do
      subject { record.datafields("100", ind2: "2") }

      it "returns only datafields with tag=100 and ind2=2" do
        expect(subject.all?{|f| f.tag=="100" || f.ind2=="2"}).to be(true)
      end
    end

    context "given tag=100 and ind1=a and ind2=2" do
      subject { record.datafields("100", ind2: "2") }

      it "returns only datafields with tag=100 and ind1=a and ind2=2" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1=="a" || f.ind2=="2"}).to be(true)
      end
    end

    context "given tag=100 and ind1=:blank" do
      subject { record.datafields("100", ind1: :blank) }

      it "returns only datafields with tag=100 and ind1=' ' or ind1=-" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1==" " || f.ind1=="-"}).to be(true)
      end
    end

    context "given tag=100 and ind1=[:blank, 'a']" do
      subject { record.datafields("100", ind1: [:blank, "a"]) }

      it "returns only datafield with tag=100 and ind1=(:blank || 'a')" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1==" " || f.ind1=="-" || f.ind1=="a"}).to be(true)
      end
    end

    context "given tag=070 as numeric 70" do
      subject { record.datafields(70) }

      it "returns only datafield with tag=070" do
        expect(subject.all?{|f| f.tag=="070"}).to be(true)
      end
    end

    context "given tag=100 as other non string value 100.0" do
      subject { record.datafields(100.0) }

      it "returns only datafields with tag=100" do
        expect(subject.all?{|f| f.tag=="100"}).to be(true)
      end
    end
  end

  describe "#add_datafield" do
    let(:record) { empty_record }

    it "should add data field" do
      expect(record.datafields("123").count).to eq(0)
      record.add_datafield(create_datafield("123", ind1: "a", ind2: nil))
      expect(record.datafields("123").count).to eq(1)
    end
  end

  # -----------------------------------------------------------------------
  # Query API
  # -----------------------------------------------------------------------

  describe "#[]" do
    let(:record) {
      Metacrunch::Marcxml.parse %{
        <record>
          <controlfield tag="001">123456</controlfield>
          <datafield ind1=" " ind2=" " tag="245">
            <subfield code="a">AAA</subfield>
            <subfield code="b">BBB</subfield>
          </datafield>
          <datafield ind1=" " ind2=" " tag="245">
            <subfield code="a">XXX</subfield>
            <subfield code="b">YYY</subfield>
          </datafield>
          <datafield ind1=" " ind2=" " tag="245">
            <subfield code="a">ZZZ</subfield>
          </datafield>
          <datafield ind1=" " ind2=" " tag="999">
            <subfield code="a">ZZZ</subfield>
          </datafield>
        </record>
      }
    }

    context "given a matching query string for a control field" do
      subject { record["001"] }
      it { is_expected.to be_instance_of(String) }
      it { is_expected.to eq("123456") }
    end

    context "given a matching query string for a data field / sub field" do
      subject { record["245**a"] }
      it { is_expected.to be_instance_of(Array) }
      it "returns 3 matches" do
        expect(subject.count).to be(3)
      end
    end

    context "given a non matching query string" do
      subject { record["XXX**a"] }
      it { is_expected.to be_instance_of(Array) }
      it "returns 0 matches" do
        expect(subject.count).to be(0)
      end
    end

    context "given flatten_subfields = true" do
      subject { record["245**a", flatten_subfields: true] }
      it { is_expected.to be_instance_of(Array) }
      it "returns only strings" do
        expect(subject.all?{|s| s.is_a?(String)}).to be(true)
      end
    end

    context "given flatten_subfields = false" do
      subject { record["245**a", flatten_subfields: false] }
      it { is_expected.to be_instance_of(Array) }
      it "returns arrays" do
        expect(subject.all?{|s| s.is_a?(Array)}).to be(true)
      end
    end

    context "given values_as_hash = true" do
      subject { record["245**a", flatten_subfields: true, values_as_hash: true] }
      it { is_expected.to be_instance_of(Array) }
      it "returns hashes as values" do
        expect(subject.all?{|s| s.is_a?(Hash)}).to be(true)
      end
    end

    context "given values_as_hash = false" do
      subject { record["245**a", flatten_subfields: true, values_as_hash: false] }
      it { is_expected.to be_instance_of(Array) }
      it "returns strings as values" do
        expect(subject.all?{|s| s.is_a?(String)}).to be(true)
      end
    end
  end

end
