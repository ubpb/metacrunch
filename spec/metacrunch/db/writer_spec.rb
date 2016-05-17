def new_db_connection
  defined?(JRUBY_VERSION) ? Sequel.connect("jdbc:sqlite::memory:") : Sequel.sqlite # in-memory db
end

describe Metacrunch::Db::Writer do

  DB = new_db_connection

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
    subject { new_db_connection }

    it "closes db connection" do
      subject.disconnect
      expect(subject.pool.available_connections).to be_empty
    end
  end

end
