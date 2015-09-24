describe Metacrunch::File::Reader::ZipFileReader do
  describe ".accepts?" do
    it "accepts filenames this reader can process" do
      expect(described_class.accepts?("foo.zip")).to equal(true)
    end

    it "does not accept filenames this reader cannot process" do
      expect(described_class.accepts?("plain_file")).to equal(false)
      expect(described_class.accepts?("plain.zip.file")).to equal(false)
      expect(described_class.accepts?("foozip")).to equal(false)
    end
  end
end
