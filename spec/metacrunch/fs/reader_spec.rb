describe Metacrunch::Fs::Reader do

  describe "#each" do
    subject { Metacrunch::Fs::Reader.new(File.join(asset_dir, "regular_file.txt")) }

    context "when called without a block" do
      it "returns an enumerator" do
        expect(subject.each).to be_a(Enumerator)
      end
    end

    context "when called with a block" do
      it "calls the block for each file" do
        entries = []
        subject.each do |file_entry|
          entries << file_entry
        end

        expect(entries.count).to be(1)
        expect(entries.first.contents).to eq("THIS IS A TEST\n")
      end
    end
  end

  context "when given a regular file" do
    subject { Metacrunch::Fs::Reader.new(File.join(asset_dir, "regular_file.txt")) }

    it "reads that file" do
      expect(subject.each.first.contents).to eq("THIS IS A TEST\n")
      expect(subject.each.first.from_archive?).to eq(false)
    end
  end

  context "when given a tar archive" do
    subject { Metacrunch::Fs::Reader.new(File.join(asset_dir, "archive.tar")) }

    it "reads the files from the archive" do
      expect(subject.each.first.contents).to eq("THIS IS A TEST\n")
      expect(subject.each.first.from_archive?).to eq(true)
    end
  end

  context "when given a compressed file (GZip)" do
    subject { Metacrunch::Fs::Reader.new(File.join(asset_dir, "regular_file.txt.gz")) }

    it "reads that file" do
      expect(subject.each.first.contents).to eq("THIS IS A TEST\n")
      expect(subject.each.first.from_archive?).to eq(false)
    end
  end

  context "when given a compressed tar archive (Gziped tar)" do
    subject { Metacrunch::Fs::Reader.new(File.join(asset_dir, "archive.tar.gz")) }

    it "reads the files from the archive" do
      expect(subject.each.first.contents).to eq("THIS IS A TEST\n")
      expect(subject.each.first.from_archive?).to eq(true)
    end
  end

end
