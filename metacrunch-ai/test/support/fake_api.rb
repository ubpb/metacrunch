# frozen_string_literal: true

require "socket"

# An HTTP/1.1 server on a free local port for unit tests: it answers requests from routes and keeps connections
# alive, or with close_after_each: true closes each one after its answer, without saying so, as a server whose
# keep-alive timeout ran out. A request without a route gets a 404.
class FakeApi

  # A request as the server saw it; headers with lowercase names.
  Request = Data.define(:verb, :path, :headers, :body) do
    def json = JSON.parse(body)
  end

  attr_reader :requests, :accepts

  def initialize(close_after_each: false)
    @close_after_each = close_after_each
    @listener = TCPServer.new("127.0.0.1", 0)
    @routes = []
    @requests = []
    @accepts = 0
    @lock = Mutex.new
    @thread = Thread.new { serve }
  end

  def url(path = "") = "http://127.0.0.1:#{@listener.addr[1]}#{path}"

  # Answers requests with method and a path equal to path (a String) or matching it (a Regexp) with the block's
  # [status, body, headers]; a Hash or Array body is sent as JSON. The newest route wins; with times: it answers
  # that many requests only.
  def on(method, path, times: nil, &answer)
    @lock.synchronize { @routes.unshift({method:, path:, times:, answer:}) }
    self
  end

  def stop
    @thread.kill.join
    @listener.close
  end

  private

  def serve
    loop do
      client = @listener.accept
      @lock.synchronize { @accepts += 1 }
      Thread.new(client) { converse(it) }
    end
  end

  def converse(client)
    while (request = read_request(client))
      @lock.synchronize { @requests << request }
      client.write(response(*answer(request)))
      break if @close_after_each
    end
  rescue IOError, SystemCallError
    nil
  ensure
    client.close
  end

  def read_request(client)
    line = client.gets or return nil
    method, path = line.split
    headers = {}
    while (header = client.gets) && header != "\r\n"
      name, value = header.split(":", 2)
      headers[name.downcase] = value.strip
    end
    body = client.read(Integer(headers.fetch("content-length", "0")))
    Request.new(verb: method, path:, headers:, body:)
  end

  def answer(request)
    route = @lock.synchronize do
      @routes.find { matches?(it, request) }&.tap { it[:times] -= 1 if it[:times] }
    end
    return [404, {"error" => "no route for #{request.verb} #{request.path}"}, {}] unless route

    status, body, headers = route[:answer].call(request)
    [status, body, headers || {}]
  end

  def matches?(route, request)
    return false if route[:times]&.zero?
    return false unless route[:method] == request.verb

    route[:path].is_a?(Regexp) ? route[:path].match?(request.path) : route[:path] == request.path
  end

  def response(status, body, headers)
    text = body.is_a?(Hash) || body.is_a?(Array) ? JSON.generate(body) : body.to_s
    lines = ["HTTP/1.1 #{status} Status", "Content-Type: application/json", "Content-Length: #{text.bytesize}"]
    lines.concat(headers.map { |name, value| "#{name}: #{value}" })
    "#{lines.join("\r\n")}\r\n\r\n#{text}"
  end

end
