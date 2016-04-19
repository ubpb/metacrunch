describe Metacrunch::Db::Reader do

  DB_URL = "sqlite://#{File.join(asset_dir, "dummy.sqlite")}"

  describe "#each" do
    subject { Metacrunch::Db::Reader.new(DB_URL, "select * from users") }

    context "when called without a block" do
      it "returns an enumerator" do
        expect(subject.each).to be_a(Enumerator)
      end
    end

    context "when called with a block" do
      it "calls the block for each row" do
        users = []
        subject.each do |row|
          users << row
        end

        expect(users.count).to be(100)
      end
    end
  end

end
