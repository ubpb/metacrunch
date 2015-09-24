describe Metacrunch::File::Reader do
  def pipeline_factory
    Class.new do
      def terminate!;  @terminated = true; end
      def terminated?; !!@terminated;      end
    end
    .new
  end

  def reader_factory(filename)
    described_class.new({
      bulk_size: 10,
      filenames: [filename],
      force_content_encoding: "utf-8"
    })
  end

  # filenames
  let(:plain_file_name) { File.join(asset_dir, "file/some_file") }
  let(:plain_gz_file_name) { File.join(asset_dir, "file/some_file.gz") }
  let(:tar_file_name) { File.join(asset_dir, "file/tar_archive.tar") }
  let(:tar_gz_file_name) { File.join(asset_dir, "file/tar_gz_archive.tar.gz") }
  let(:tgz_file_name) { File.join(asset_dir, "file/tgz_archive.tgz") }
  let(:zip_file_name) { File.join(asset_dir, "file/zip_archive.zip") }

  # readers
  let(:plain_file_reader) { reader_factory(plain_file_name) }
  let(:plain_gz_file_reader) { reader_factory(plain_gz_file_name) }
  let(:tar_reader) { reader_factory(tar_file_name) }
  let(:tar_gz_reader) { reader_factory(tar_gz_file_name) }
  let(:tgz_reader) { reader_factory(tgz_file_name) }
  let(:zip_reader) { reader_factory(zip_file_name) }

  describe "#call" do
    it "fills items with #{_file_type = Metacrunch::File} objects" do
      [plain_file_reader, plain_gz_file_reader, tar_reader, tar_gz_reader,tgz_reader, zip_reader].each do |_reader|
        pipeline = pipeline_factory

        _reader.call(items = [], pipeline)
        expect(items.length).not_to eq(0)
        expect(items).to all(be_a(_file_type))

        _reader.call(items, pipeline) until pipeline.terminated?
      end
    end
  end
end
