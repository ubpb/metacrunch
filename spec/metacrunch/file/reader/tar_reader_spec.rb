describe Metacrunch::File::Reader::TarFileReader do
  describe ".accepts?" do
    it "accepts filenames this reader can process" do
      expect(described_class.accepts?("foo.tar")).to equal(true)
      expect(described_class.accepts?("foo.tar.gz")).to equal(true)
      expect(described_class.accepts?("foo.tgz")).to equal(true)
    end

    it "does not accept filenames this reader cannot process" do
      expect(described_class.accepts?("plain_file")).to equal(false)
      expect(described_class.accepts?("plain_file.gz")).to equal(false)
      expect(described_class.accepts?("tatar.gz")).to equal(false)
    end
  end
end
