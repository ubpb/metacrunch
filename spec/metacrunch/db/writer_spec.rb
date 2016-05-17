describe Metacrunch::Db::Writer do

  DB = Sequel.sqlite # in-memory db

  before(:all) do
    DB.create_table(:users) do
      primary_key :id
      String :name
    end
  end

  describe "#write" do
    subject { Metacrunch::Db::Writer.new(DB, ->(db){ db[:users] }) }

    it "writes data into database" do
      10.times do |i|
        subject.write({id: i, name: "name-#{i}"})
      end

      expect(DB[:users].count).to be(10)
    end
  end

  describe "#close" do
    subject { Sequel.sqlite }

    it "closes db connection" do
      subject.disconnect
      expect(subject.pool.available_connections).to be_empty
    end
  end

end
