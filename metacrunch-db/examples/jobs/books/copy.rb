# frozen_string_literal: true

Metacrunch.job "books:copy", desc: "Copy the table books into another database" do
  params do
    instance_exec(&Metacrunch::Db.connection_params("source"))
    instance_exec(&Metacrunch::Db.connection_params("target"))
  end

  source Metacrunch::Db::Reader.new(Metacrunch::Db::Connection.from_params(params, prefix: "source"),
                                    table: "books", count: true)
  sink Metacrunch::Db::Writer.new(Metacrunch::Db::Connection.from_params(params, prefix: "target"),
                                  table: "books", action: :upsert, key: "isbn"),
       batch: 1000
end
