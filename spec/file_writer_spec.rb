describe Metacrunch::FileWriter do

  let(:regular_file)    { "/tmp/metacrunch_spec_regular_file.txt" }
  let(:compressed_file) { "/tmp/metacrunch_spec_regular_file.txt.gz" }

  before do
    ::File.unlink(regular_file)    if ::File.exist?(regular_file)
    ::File.unlink(compressed_file) if ::File.exist?(compressed_file)
  end

  it "can write a file" do
    writer = Metacrunch::FileWriter.new(regular_file)
    writer.write("FOO")
    writer.write("BAR")
    writer.close

    content = File.read(regular_file)
    expect(content).to eq("FOOBAR")
  end

  it "can write a compressed file" do
    writer = Metacrunch::FileWriter.new(compressed_file, compress: true)
    writer.write("FOO")
    writer.write("BAR")
    writer.close

    io      = Zlib::GzipReader.open(compressed_file)
    content = io.read
    io.close

    expect(content).to eq("FOOBAR")
  end

  it "can override existing file" do
    ::File.write(regular_file, "FOO")

    expect {
      Metacrunch::FileWriter.new(regular_file)
    }.to raise_error(Metacrunch::FileWriter::FileExistError)

    expect {
      Metacrunch::FileWriter.new(regular_file, override: true)
    }.not_to raise_error
  end

end
