# frozen_string_literal: true

# Keeps the public title records and reduces them to some fields; a record
# without one of them fails. A transform has steps and parameters but no
# source and no sink: the jobs that use it decide where records come from
# and go to. Alone it reads JSON Lines from stdin and writes them to stdout.
#
#   cd examples/project
#   bundle exec metacrunch run catalog:public --help
#   bundle exec metacrunch run catalog:public --fields id < data/titles.jsonl
Metacrunch.transform "catalog:public", desc: "Keep the public titles, reduced to some fields" do
  params do
    param :fields, Array, default: ["id", "title"], desc: "Fields to keep"
  end

  reject("Not public") { !it["public"] }
  map { |record| params.fields.to_h { [it, record.fetch(it)] } }
end
