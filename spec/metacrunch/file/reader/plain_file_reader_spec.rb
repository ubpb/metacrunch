describe Metacrunch::File::Reader::PlainFileReader do
  describe ".accepts?" do
    it "accepts all filenames" do
      expect(described_class.accepts?("foo")).to equal(true)
      expect(described_class.accepts?("foo.gz")).to equal(true)
      expect(described_class.accepts?("foo.tar.gz")).to equal(true)
      expect(described_class.accepts?("foo.xml")).to equal(true)
      expect(described_class.accepts?("foo.zip")).to equal(true)
    end
  end
end
