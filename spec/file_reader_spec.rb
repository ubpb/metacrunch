describe Metacrunch::FileReader do

  let(:regular_file) { File.join(RSpec.root, "assets", "regular_file.txt") }
  let(:compressed_regular_file) { File.join(RSpec.root, "assets", "regular_file.txt.gz") }
  let(:archive_file) { File.join(RSpec.root, "assets", "archive.tar") }
  let(:compressed_archive_file) { File.join(RSpec.root, "assets", "archive.tar.gz") }

  it "can read a single file" do
    reader = Metacrunch::FileReader.new(regular_file)
    expect(reader.each.count).to be(1)
  end

  it "can read multiple files" do
    reader = Metacrunch::FileReader.new([regular_file, regular_file])
    expect(reader.each.count).to be(2)
  end

  it "can read regular files" do
    reader = Metacrunch::FileReader.new(regular_file)
    reader.each do |entry|
      expect(entry).to be_instance_of(Metacrunch::FileReader::Entry)
      expect(entry.filename).to eq(regular_file)
      expect(entry.archive_filename).to be_nil
      expect(entry.from_archive?).to be false
      expect(entry.contents).to eq("THIS IS A TEST\n")
    end
  end

  it "can read compressed regular files" do
    reader = Metacrunch::FileReader.new(compressed_regular_file)
    reader.each do |entry|
      expect(entry).to be_instance_of(Metacrunch::FileReader::Entry)
      expect(entry.filename).to eq(compressed_regular_file)
      expect(entry.archive_filename).to be_nil
      expect(entry.from_archive?).to be false
      expect(entry.contents).to eq("THIS IS A TEST\n")
    end
  end

  it "can read TAR archives" do
    reader = Metacrunch::FileReader.new(archive_file)
    reader.each do |entry|
      expect(entry).not_to be_nil
      expect(entry).to be_instance_of(Metacrunch::FileReader::Entry)
      expect(entry.filename).to eq(archive_file)
      expect(entry.archive_filename).to eq("regular_file.txt")
      expect(entry.from_archive?).to be true
      expect(entry.contents).to eq("THIS IS A TEST\n")
    end
  end

  it "can read compressed TAR archives" do
    reader = Metacrunch::FileReader.new(compressed_archive_file)
    reader.each do |entry|
      expect(entry).not_to be_nil
      expect(entry).to be_instance_of(Metacrunch::FileReader::Entry)
      expect(entry.filename).to eq(compressed_archive_file)
      expect(entry.archive_filename).to eq("regular_file.txt")
      expect(entry.from_archive?).to be true
      expect(entry.contents).to eq("THIS IS A TEST\n")
    end
  end

  describe ".each()" do
    context "when called without a block" do
      it "returns an enumerator" do
        reader = Metacrunch::FileReader.new(regular_file)
        expect(reader.each).to be_instance_of(Enumerator)
      end
    end
  end

end
