describe Metacrunch::TarWriter do

  let(:regular_tar_file)    { "/tmp/metacrunch_spec_regular_file.tar" }
  let(:compressed_tar_file) { "/tmp/metacrunch_spec_regular_file.tar.gz" }

  before do
    File.unlink(regular_tar_file)    if File.exist?(regular_tar_file)
    File.unlink(compressed_tar_file) if File.exist?(compressed_tar_file)
  end

  it "can write a file" do
    writer = Metacrunch::TarWriter.new(regular_tar_file)
    writer.write("FOO", filename: "foo.txt")
    writer.write("BAR", filename: "bar.txt")
    writer.close

    files = Metacrunch::FileReader.new(regular_tar_file).each
    expect(files.count).to eq(2)
    expect(files.first.contents).to eq("FOO")
  end

  it "can write a compressed file" do
    writer = Metacrunch::TarWriter.new(compressed_tar_file)
    writer.write("FOO", filename: "foo.txt")
    writer.write("BAR", filename: "bar.txt")
    writer.close

    files = Metacrunch::FileReader.new(compressed_tar_file).each
    expect(files.count).to eq(2)
    expect(files.first.contents).to eq("FOO")
  end

end
