# frozen_string_literal: true

require "socket"

# A server on a free local port that answers HELLO with a RESP3 map of server and version, and every other command
# with +OK, so Connection#connect can be tested without Redis. It notes the commands it got.
class TinyServer

  attr_reader :port, :commands

  def initialize(server: "redis", version: "8.10.3")
    @hello = {"server" => server, "version" => version, "proto" => "3"}
    @listener = TCPServer.new("127.0.0.1", 0)
    @port = @listener.addr[1]
    @commands = Queue.new
    @thread = Thread.new { serve }
  end

  def url = "redis://127.0.0.1:#{port}/0"

  def stop
    @thread.kill.join
    @listener.close
  end

  private

  def serve
    loop do
      client = @listener.accept
      Thread.new(client) { answer(it) }
    end
  end

  def answer(client)
    while (command = read_command(client))
      @commands << command
      client.write(command.first.casecmp?("HELLO") ? hello : "+OK\r\n")
    end
  ensure
    client.close
  end

  def hello = "%#{@hello.size}\r\n#{@hello.map { |key, value| "+#{key}\r\n+#{value}\r\n" }.join}"

  # *N, then N bulk strings: $LENGTH and the bytes.
  def read_command(client)
    header = client.gets or return nil
    Array.new(Integer(header[1..])) do
      length = Integer(client.gets[1..])
      client.read(length + 2).chomp
    end
  end

end
