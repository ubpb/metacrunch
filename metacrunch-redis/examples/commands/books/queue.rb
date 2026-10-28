# frozen_string_literal: true

Metacrunch.command "books:queue", desc: "Show how many books the queue holds, or empty it" do
  params do
    use Metacrunch::Redis::CONNECTION_PARAMS
    param :queue, String, default: "books", desc: "the queue"
    param :clear, :bool, default: false, desc: "empty the queue"
  end

  run do
    Metacrunch::Redis::Connection.from_params(params).connect do |redis|
      if params.clear
        redis.call("DEL", params.queue)
        puts "#{params.queue}: emptied"
      else
        puts "#{params.queue}: #{redis.call("LLEN", params.queue)} entries"
      end
    end
  end
end
