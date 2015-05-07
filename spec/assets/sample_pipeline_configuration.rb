pipeline do
  reader "Metacrunch::Loopback::Reader", {
    items: [1,2,3,4,5,6,7,8,9,10],
    bulk_size: 2
  }

  processor -> (items, pipeline) do
    items.map! do |_item|
      _item * 2
    end
  end

  processor "Metacrunch::Loopback::Buffer", {
    size: 4  
  }
    
  writer "Metacrunch::Stdout::Writer"
end
