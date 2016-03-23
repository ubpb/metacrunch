describe Metacrunch::Hash do
  describe ".add" do
    it "adds the given key/value pair" do
      described_class.add(hash = {}, :key, "value")
      expect(hash[:key]).to eq("value")
    end

    it "respects the type of the key" do
      hash = {}

      described_class.add(hash, :symbol_key1, "value")
      described_class.add(hash, ":symbol_key2", "value")
      described_class.add(hash, "string_key", "value")

      expect(hash[:symbol_key1]).to eq("value")
      expect(hash[:symbol_key2]).to eq("value")
      expect(hash["string_key"]).to eq("value")
    end

    context "if wrong arguments are given" do
      it "raises an #{exception_type = ArgumentError}" do
        expect { described_class.add(hash) }.to raise_error(exception_type)
      end
    end

    context "if key includes forward dashes" do
      it "splits the key by forward dashes" do
        described_class.add(hash = {}, "key/subkey", "value")
        expect(hash["key"]["subkey"]).to eq("value")
      end

      it "respects the type of the keys" do
        described_class.add(hash = {}, "key/:subkey/sub_sub_key", "value")
        expect(hash["key"][:subkey]["sub_sub_key"]).to eq("value")
      end
    end

    context "if multiple keys are given" do
      it "dives into the object and adds the key/value pair" do
        hash = { "key" => { "subkey" => "former_value" } }
        described_class.add(hash, "key", "subkey", "value")
        expect(hash["key"]["subkey"]).to eq(["former_value", "value"])
      end
    end

    context "if there already exists a value for the given key" do
      context "if the value is an array" do
        it "adds the value to the array" do
          hash = { "key" => ["former_value1", "former_value2"] }
          described_class.add(hash, "key", "value")
          expect(hash["key"]).to eq(["former_value1", "former_value2", "value"])
        end

        it "returns aggregated value" do
          hash = { "key" => ["former_value1", "former_value2"] }
          expect(described_class.add(hash, "key", "value")).to eq(["former_value1", "former_value2", "value"])
        end
      end

      it "makes the existing value an array and adds the given value" do
        hash = { "key" => "former_value" }
        described_class.add(hash, "key", "value")
        expect(hash["key"]).to eq(["former_value", "value"])
      end

      it "returns aggregated value" do
        hash = { "key" => "former_value" }
        expect(described_class.add(hash, "key", "value")).to eq(["former_value", "value"])
      end
    end

    context "if the given value is nil" do
      it "does not add anything" do
        described_class.add(hash = {}, "key/subkey", nil)
        expect(hash).to eq({})
      end
    end

    context "if the given value is empty" do
      it "does not add anything" do
        hash = {}
        described_class.add(hash, "key/subkey1", "")
        described_class.add(hash, "key/subkey2", [])
        described_class.add(hash, "key/subkey3", Class.new { def empty?; true; end }.new)
        expect(hash).to eq({})
      end
    end

    it "returns the value" do
      expect(described_class.add({}, "key", "value")).to eq("value")
    end
  end
end
