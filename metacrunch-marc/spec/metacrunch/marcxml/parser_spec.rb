describe Metacrunch::Marcxml::Parser do

  describe "#parse" do
    context "given invalid MarcXML" do
      subject {
        described_class.new.parse <<-XML
          <XXX_record>
            <controlfield tag="XXX">123456</controlfield>
          </XXX_record>
        XML
      }

      it "should return nil" do
        expect(subject).to be_nil
      end
    end

    context "given a MarcXML with a control field" do
      subject {
        described_class.new.parse <<-XML
          <record>
            <controlfield tag="XXX">123456</controlfield>
          </record>
        XML
      }

      it "should return a Marcxml::Document" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end

      it "should have created the control field" do
        controlfields_map = subject.instance_variable_get("@controlfields_map")
        expect(controlfields_map.count).to eq(1)

        controlfield = subject.instance_variable_get("@controlfields_map")["XXX"]
        expect(controlfield).to be_instance_of(Metacrunch::Marcxml::Document::Controlfield)
        expect(controlfield.tag).to eq("XXX")
        expect(controlfield.value).to eq("123456")
      end
    end

    context "given a MarcXML with a data field / sub field" do
      subject {
        described_class.new.parse <<-XML
          <record>
            <datafield tag="XXX" ind1="1" ind2="2">
              <subfield code="a">123456</subfield>
            </datafield>
          </record>
        XML
      }

      it "should return a Marcxml::Document" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end

      it "should have created the data field" do
        datafields_map = subject.instance_variable_get("@datafields_map")
        expect(datafields_map.count).to eq(1)

        datafields = datafields_map["XXX"]
        expect(datafields.count).to eq(1)

        datafield = datafields.first
        expect(datafield).to be_instance_of(Metacrunch::Marcxml::Document::Datafield)
        expect(datafield.tag).to eq("XXX")
        expect(datafield.ind1).to eq("1")
        expect(datafield.ind2).to eq("2")
      end

      it "should have created the sub field" do
        datafields_map = subject.instance_variable_get("@datafields_map")
        datafield      = datafields_map["XXX"].first
        subfields_map  = datafield.instance_variable_get("@subfields_map")
        expect(subfields_map.count).to eq(1)

        subfields = subfields_map["a"]
        expect(subfields.count).to eq(1)

        subfield = subfields.first
        expect(subfield).to be_instance_of(Metacrunch::Marcxml::Document::Subfield)
        expect(subfield.code).to eq("a")
        expect(subfield.value).to eq("123456")
      end
    end

    context "given a MarcXML with sub field values with HTML entities" do
      subject {
        described_class.new.parse <<-XML
          <record>
            <datafield tag="XXX" ind1="1" ind2="2">
              <subfield code="a">&lt;&lt;Some&gt;&gt; HTML Entities: &eacute; &#123; &#x12a;</subfield>
            </datafield>
          </record>
        XML
      }

      it "decodes html entities" do
        datafields_map = subject.instance_variable_get("@datafields_map")
        datafield      = datafields_map["XXX"].first
        subfields_map  = datafield.instance_variable_get("@subfields_map")
        expect(subfields_map.count).to eq(1)

        subfields = subfields_map["a"]
        expect(subfields.count).to eq(1)

        subfield = subfields.first
        expect(subfield.value).to eq("<<Some>> HTML Entities: é { Ī")
      end
    end

    context "given a nested MarcXML" do
      subject {
        described_class.new.parse <<-XML
          <OAI-PMH>
            <ListRecords>
              <record>
                <header>
                  <identifier>aleph-publish:000969442</identifier>
                </header>
                <metadata>
                  <record>
                    <controlfield tag="XXX">123456</controlfield>
                  </record>
                </metadata>
              </record>
            </ListRecords>
          </OAI-PMH>
        XML
      }

      it "should return a Marcxml::Document" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end

      it "should have created the control field" do
        controlfields_map = subject.instance_variable_get("@controlfields_map")
        expect(controlfields_map.count).to eq(1)

        controlfield = subject.instance_variable_get("@controlfields_map")["XXX"]
        expect(controlfield).to be_instance_of(Metacrunch::Marcxml::Document::Controlfield)
        expect(controlfield.tag).to eq("XXX")
        expect(controlfield.value).to eq("123456")
      end
    end

  end

end
