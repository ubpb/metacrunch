describe Metacrunch::File do
  describe "#to_h" do
    let(:file) do
      described_class.new({
        content: "content",
        entry_name: "entry_name",
        file_name: "file_name"
      })
    end

    it "returns a hash representation of the file object" do
      expect(file.to_h).to be_a(Hash)
    end
  end
end
