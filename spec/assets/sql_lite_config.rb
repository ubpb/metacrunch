pipeline do
  reader "Metacrunch::Archive::Reader", {
    bulk_size: 2,
    filenames: "foo.tar.gz"
  }

  processor -> (items, pipeline) {
    items.map! do |_item|

    end
  }
  #processor "Metacrunch::Sqlite::Writer", {
  #  database: "mab_xml.db"
  #}

  processor "Metacrunch::Debugger"
end
