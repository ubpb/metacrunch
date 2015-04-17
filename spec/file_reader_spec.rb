describe Metacrunch::Utils::FileReader do

  let(:reader) { Metacrunch::Utils::FileReader.new }
  let(:regular_file) { File.join(RSpec.root, "assets", "regular_file.txt") }
  let(:compressed_regular_file) { File.join(RSpec.root, "assets", "regular_file.txt.gz") }
  let(:archive_file) { File.join(RSpec.root, "assets", "archive.tar") }
  let(:compressed_archive_file) { File.join(RSpec.root, "assets", "archive.tar.gz") }

  it "can read regular files" do
    reader.read_files(regular_file) do |result|
      expect(result).not_to be_nil
      expect(result).to be_instance_of(Metacrunch::Utils::FileReaderResult)
      expect(result.filename).to eq(regular_file)
      expect(result.source_filename).to be_nil
      expect(result.from_archive?).to be false
      expect(result.contents).to eq("THIS IS A TEST\n")
    end
  end

  it "can read compressed regular giles" do
    reader.read_files(compressed_regular_file) do |result|
      expect(result).not_to be_nil
      expect(result).to be_instance_of(Metacrunch::Utils::FileReaderResult)
      expect(result.filename).to eq(compressed_regular_file)
      expect(result.source_filename).to be_nil
      expect(result.from_archive?).to be false
      expect(result.contents).to eq("THIS IS A TEST\n")
    end
  end

  it "can read TAR archives" do
    reader.read_files(archive_file) do |result|
      expect(result).not_to be_nil
      expect(result).to be_instance_of(Metacrunch::Utils::FileReaderResult)
      expect(result.filename).to eq("regular_file.txt")
      expect(result.source_filename).to eq(archive_file)
      expect(result.from_archive?).to be true
      expect(result.contents).to eq("THIS IS A TEST\n")
    end
  end

  it "can read compressed TAR archives" do
    reader.read_files(compressed_archive_file) do |result|
      expect(result).not_to be_nil
      expect(result).to be_instance_of(Metacrunch::Utils::FileReaderResult)
      expect(result.filename).to eq("regular_file.txt")
      expect(result.source_filename).to eq(compressed_archive_file)
      expect(result.from_archive?).to be true
      expect(result.contents).to eq("THIS IS A TEST\n")
    end
  end

end
