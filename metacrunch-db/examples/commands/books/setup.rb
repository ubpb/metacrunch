# frozen_string_literal: true

Metacrunch.command "books:setup", desc: "Create the table books unless it exists" do
  params { instance_exec(&Metacrunch::Db::CONNECTION_PARAMS) }

  run do
    Metacrunch::Db::Connection.from_params(params).connect do |db|
      db.create_table?(:books) do
        String :isbn, primary_key: true, size: 13
        String :title, null: false, size: 200
        String :author, size: 200
        Integer :year
        Date :added_on
      end
    end
  end
end
