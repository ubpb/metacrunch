# frozen_string_literal: true

# Lets the commands, which build their connection from their params, talk to
# a FakeElasticsearch: inside with_fake_elasticsearch(fake) { ... },
# Connection.from_params returns fake's connection.
module FakeConnections

  def from_params(params)
    fake = Thread.current[:fake_elasticsearch]
    fake ? fake.connection : super
  end

  def self.use(fake)
    Thread.current[:fake_elasticsearch] = fake
    yield
  ensure
    Thread.current[:fake_elasticsearch] = nil
  end

end

Metacrunch::Elasticsearch::Connection.singleton_class.prepend(FakeConnections)
