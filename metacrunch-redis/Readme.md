# metacrunch-redis

Redis for [metacrunch](https://github.com/ubpb/metacrunch): a queue between jobs, whose producers pause while Redis is
full and whose consumers wait for new entries, and a source and a sink for values under keys, on Redis and Valkey.

A producer pushes records into a queue:

```ruby
require "metacrunch/redis"

Metacrunch.job do
  params do
    use Metacrunch::Redis::CONNECTION_PARAMS
    args :files, min: 1
  end

  redis = Metacrunch::Redis::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.files)
  sink Metacrunch::Redis::QueueWriter.new(redis, queue: "books", max_length: 100_000), batch: 100
end
```

Consumers, on as many machines as you like, take them and wait for more:

```ruby
require "metacrunch/redis"
require "metacrunch/elasticsearch"

Metacrunch.job do
  params do
    use Metacrunch::Redis.connection_params("redis")   # --redis-url, --redis-user, --redis-password
    use Metacrunch::Elasticsearch::CONNECTION_PARAMS
  end

  redis = Metacrunch::Redis::Connection.from_params(params, prefix: "redis")
  source Metacrunch::Redis::QueueReader.new(redis, queue: "books", wait: true)
  map { |book| book.slice("isbn", "title", "author") }
  sink Metacrunch::Elasticsearch::Writer.new(Metacrunch::Elasticsearch::Connection.from_params(params),
                                             index: "books", id: "isbn"), batch: 1000
end
```

```
$ metacrunch run jobs/enqueue.rb --url redis://redis.example.org:6379/0 books-*.jsonl
$ metacrunch run -w 4 jobs/consume.rb --redis-url redis://redis.example.org:6379/0 --url https://es.example.org:9200
```

More in [`examples/`](examples): a project that fills a queue, consumes it, caches books under keys and exports them.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-redis"
end
```

Requires Ruby 4.0, metacrunch in the same version as this gem, and Redis 7 or later or Valkey (any version). It talks
to the server with [redis-client](https://github.com/redis-rb/redis-client), the client redis-rb is built on. Tested
with Redis 7.2, Redis 8.10 and Valkey 9.1. Redis Cluster and Sentinel are not supported.

## Connection

```ruby
redis = Metacrunch::Redis::Connection.new(url: "redis://localhost:6379/0")
redis = Metacrunch::Redis::Connection.new(url: "rediss://redis.example.org:6380/2", user: "etl", password: password)
```

| Option | | |
|---|---|---|
| `url` | required | `redis://host:port/db`, `rediss://` for TLS, or `unix:///path/to/redis.sock`; `user:password@` in it counts as `user` and `password` |
| `user`, `password` | | the login (a user of Redis's ACL, or only the password); not together with user info in the URL |
| any other | | passed to `RedisClient.config`, e.g. `connect_timeout:`, `read_timeout:`, `write_timeout:` (seconds, 1 by default), `ssl_params:`, `id:` (the client's name), `driver: :hiredis` (with the gem `hiredis-client`) |

A connection is a value: building one connects nowhere, so `--help`, `check` and `Metacrunch::Testing` need no
server. Every reader and writer opens a client of its own from it when the job opens it, and closes it when the job
closes it; `connect` says `HELLO` at once, so a wrong host or password stops the job before the first record, and so
does a Redis older than 7. `inspect` and the messages never show the password.

`connection.connect` returns a `RedisClient` of your own, and with a block closes it afterwards, e.g. in a command:

```ruby
Metacrunch::Redis::Connection.from_params(params).connect do |redis|
  puts "books: #{redis.call("LLEN", "books")} entries"
end
```

The same parameters for jobs and commands, as a
[group of parameters](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#groups-of-parameters)
(`params { use Metacrunch::Redis::CONNECTION_PARAMS }`): `--url`, `--user` and `--password`. The password is a
[secret](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#secrets), hidden in `--help`, messages
and `inspect`. A [params file](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#parameter-files)
gives them per [environment](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/environments.md), the
password from an environment variable or the
[credentials](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/credentials.md). Give it apart from the
URL: `url` is a plain parameter, which messages may show.

```yaml
# params.yml
default:
  url: redis://localhost:6379/0

production:
  url: rediss://redis.example.org:6380/0
  user: etl
  password: {credential: redis.password}
```

A job with two servers declares the parameters with a prefix each: `Metacrunch::Redis.connection_params("source")`
gives `--source-url`, `--source-user` and `--source-password`, read by `Connection.from_params(params, prefix:
"source")`.

## Queues

A queue is a Redis list: `QueueWriter` pushes records to its tail, `QueueReader` takes them from its head, first in,
first out. Each entry goes to one reader, so any number of consumers can share a queue, on one machine or many.

### Writing

```ruby
sink Metacrunch::Redis::QueueWriter.new(redis, queue: "books"), batch: 100
sink Metacrunch::Redis::QueueWriter.new(redis, queue: "books", max_length: 100_000, pause: 5), batch: 100
```

| Option | Default | |
|---|---|---|
| `queue` | | the key of the list |
| `format` | `:json` | `:json`: every record as JSON; `:string`: records that are Strings, as they are |
| `max_length` | | pause while the queue holds this many entries or more |
| `pause` | `1` | seconds between two tries while the writer waits |
| `max_bytes` | 1 MiB | the upper limit of the entries of one `RPUSH` |

Every record is one entry. Use the writer with `batch:`: a batch goes out as one `RPUSH` (one per `max_bytes`),
where without it every record costs a round trip to the server (about 10 000 records/s against 500 000 with batches
of 100, measured locally). A record that is not JSON (`Float::NAN`, a `Time`; with `format: :string` anything but a
String) is a failed record for the
[failure policy](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#failures); the others are
written.

The writer waits instead of failing when the consumers fall behind:

- **Redis is full.** With `maxmemory` set, Redis refuses writes when it reaches it ("OOM command not allowed"). The
  writer waits `pause` seconds and sends the same `RPUSH` again, until the consumers have taken enough entries. A
  refused `RPUSH` writes none of its entries, so nothing is lost or written twice.
- **The queue is long.** With `max_length`, the writer waits while the queue holds that many entries. Several
  producers can overshoot it by a batch each. A limit keeps a queue from growing without `maxmemory`, or from taking
  all of it.

It logs when it starts to wait and when it goes on, and waits without end. SIGTERM or Ctrl-C stop it, and the batch
it was writing is not written: a producer that reads files is run again. In a job whose source is a `QueueReader`
(from one queue into another), SIGTERM stops the reader and the writer gives up its wait at once; the run then fails
with "redis queue books: stopped while waiting for consumers; 100 records of the batch were not written", since
those records were taken from the first queue.

```
08:12:01 WARN  redis queue books: Redis is full (maxmemory); waiting for consumers to take entries
08:12:43 INFO  redis queue books: going on after 42 s
```

Set `maxmemory-policy noeviction` (Redis's default) on a server that holds queues: with an eviction policy such as
`allkeys-lru`, a full Redis deletes keys instead of refusing writes, entries of queues among them. A `volatile-`
policy deletes only keys with an expiry, which queues have not, but the writer pauses only when none of them are left.
The writer warns when it opens on a server with another policy, also without `maxmemory`, since `CONFIG SET
maxmemory` takes effect at once. Persistence (RDB snapshots, the AOF) is Redis's configuration.

When the connection breaks, the writer stops the run: it cannot know whether the last `RPUSH` arrived, and sending it
again could write its entries twice.

### Reading

```ruby
source Metacrunch::Redis::QueueReader.new(redis, queue: "books")              # until the queue is empty
source Metacrunch::Redis::QueueReader.new(redis, queue: "books", wait: true)  # waits for new entries, without end
source Metacrunch::Redis::QueueReader.new(redis, queue: "books", wait: 300)   # ends after 5 minutes without entries
```

| Option | Default | |
|---|---|---|
| `queue` | | the key of the list |
| `wait` | `false` | `false`: end when the queue is empty; `true`: wait for new entries without end; seconds: end when no entry came for that long |
| `format` | `:json` | `:json`: parse every entry; `:string`: yield the entries as Strings |
| `fetch` | `100` | entries taken per round trip |
| `flush_after` | `1` | with `wait`: seconds after which the records read are written at the latest |

Without `wait` the reader takes the queue until it is empty, which suits a consumer that starts after its producer:
the progress display shows the share taken. With `wait: true` it is a consumer that runs until it is stopped, with
`wait: seconds` one that ends when the queue stayed empty that long, say after a load. An entry that is not valid JSON
is a failed record (`Metacrunch::InvalidRecord`).

While it waits, the reader makes sure that what it read is written: `flush_after` seconds after it took a record, it
has the job write what the sinks hold for `batch:`, and what the workers of `-w` hold, by yielding
[`Metacrunch::FLUSH`](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#sources), also between
the records of a group when the steps are slow. So a consumer with `batch: 1000` writes a record within about a second
plus the time of the record's steps, also when only a few come in, and a busy one still writes full batches. Sinks
that write files (JSON Lines, CSV, MARC) flush them then, so a reader of the file sees the records.

With `wait`, a lost connection (a restart of Redis, a failover) does not end the reader, nor a server that is not
ready yet (`LOADING` while it reads its data after a restart, `BUSY` while a script runs): it logs it, tries again
after 1, 2, 4, 8, 16 and then every 30 seconds, and goes on when the server is back; with `wait: seconds` it gives up
when the quiet time is over, counted from the end of the last group of entries. Without `wait` a lost connection stops the run. A reader that cannot connect when it
opens stops the run at once, so a supervisor sees it.

### Running consumers

`metacrunch run` ends a consumer gracefully on SIGTERM: the reader stops taking entries, the records under way are
processed and written, and the run ends normally with exit code 0. Without workers that takes about a second plus the
steps of one record; with `-w`, the workers first process the batches they hold, which can take longer, so leave
enough time before a supervisor sends SIGKILL. Entries the reader took but had not handed on yet go back to the head
of the queue, also while Redis is full (for up to ten seconds). A second SIGTERM stops it at once, and so does Ctrl-C
(SIGINT), which also reaches the workers of `-w`. A command that invokes a consumer ends by SIGTERM once the consumer
has ended.

With workers, send SIGTERM to the main process only, as `kill PID` and `docker stop` do; a signal to the whole
process group ends the workers, and the run stops at once. Under systemd:

```ini
# /etc/systemd/system/books-consumer.service
[Service]
WorkingDirectory=/srv/books
ExecStart=/usr/bin/bundle exec metacrunch run -w 4 -e production --params params.yml books:consume
KillMode=mixed
TimeoutStopSec=60
Restart=always
```

`KillMode=mixed` sends SIGTERM to the main process and, after `TimeoutStopSec`, SIGKILL to all of them; size it for the
batches the workers hold. `Restart` starts a consumer again that stopped by an error, say because Redis was down when
it started.

### Delivery

A queue delivers each entry at most once: an entry leaves Redis when a reader takes it.

| The consumer ... | The entries it took |
|---|---|
| ends normally, also after SIGTERM | all written; entries not yet handed on go back to the queue |
| stops by an error, `--limit`, a second SIGTERM or Ctrl-C | what the sinks buffer is written; entries not yet handed on go back; the record a step was working on is lost, with workers the records in their batches too |
| is killed (SIGKILL, a crash of the machine) | lost: up to `fetch` entries, the records in steps and worker batches, the sinks' buffers |
| loses its connection while the server sends it entries | lost: the entries of that answer |

Stop consumers with SIGTERM, and keep the producer able to run again (a load by date or by file) where no entry may
be lost. A smaller `fetch` holds fewer entries in the consumer.

## Keys

### Writing

```ruby
sink Metacrunch::Redis::KeyWriter.new(redis, key: "book:%{isbn}", expire: 86_400), batch: 1000
sink Metacrunch::Redis::KeyWriter.new(redis, key: ->(book) { "book:#{book["isbn"].delete("-")}" },
                                             action: ->(book) { book["deleted"] ? :delete : :set }), batch: 1000
```

| Option | Default | |
|---|---|---|
| `key` | | a template, `%{name}` for the value of the record's field `name`, or a callable that returns the key of a record |
| `action` | `:set` | `:set`, `:delete`, or a callable that returns one per record |
| `format` | `:json` | `:json`: every record as JSON; `:string`: records that are Strings, as they are |
| `expire` | | seconds until a key set expires |
| `max_bytes` | 1 MiB | the upper limit of the keys and values of one pipeline |

Every record is the value of one key, written with `SET` (and `EX` for `expire`) or removed with `DEL`. A template
takes the fields of a Hash record, as Strings or Integers (`"%{type}:%{id}"`); a template without a placeholder is
one key for every record. A record without a key, with an unknown action or with a value the format cannot write is a
failed record; the others are written. A batch goes out pipelined, in the order of the records, so the last record of
a key wins. Any error of Redis stops the run, also a full Redis: `SET` and `DEL` can be repeated, so run the job
again.

### Reading

```ruby
source Metacrunch::Redis::KeyReader.new(redis, match: "book:*")
```

| Option | Default | |
|---|---|---|
| `match` | | a pattern of Redis: `*`, `?`, `[abc]` |
| `format` | `:json` | `:json`: parse every value; `:string`: the values as Strings |
| `fetch` | `1000` | the `COUNT` of `SCAN`, keys looked at per round trip |

The reader yields `{"key" => "book:9780140449136", "value" => {...}}` for every key that matches and holds a String;
keys of other types are skipped. It scans with `SCAN` and reads each page with `MGET`, so it never blocks the server.
Redis returns every key that exists during the whole scan, but may return one twice when the database changes
meanwhile. A value that is not valid JSON is a failed record, with key and value as its raw data.

## Lookups in steps

A step that looks up values opens a client of its own, so each worker of `-w` has one:

```ruby
class Authors
  def initialize(connection) = @connection = connection
  def open(_context) = @redis = @connection.connect
  def call(book) = book.merge("author" => JSON.parse(@redis.call("GET", "author:#{book["author_id"]}") || "null"))
  def close = @redis&.close
end

map Authors.new(redis)
```

## Testing jobs

`Metacrunch::Testing.run` replaces the source and the sinks and opens neither, so a job with these readers and writers
runs in tests without a server. The connection parameters still need a value, a Redis URL:

```ruby
result = Metacrunch::Testing.run(PROJECT, "books:consume", params: {url: "redis://unused"}, source: books)
```

## Running the tests of this gem

The unit tests need no server. The integration tests run against each server whose URL is set and are skipped
otherwise; [`test/compose.yml`](test/compose.yml) starts the servers with Docker. The fourth one is for the test that
fills Redis up to its `maxmemory`:

```
$ docker compose -f test/compose.yml up -d --wait
$ export TEST_REDIS_URL=redis://127.0.0.1:6380/0
$ export TEST_REDIS_7_URL=redis://127.0.0.1:6381/0
$ export TEST_VALKEY_URL=redis://127.0.0.1:6382/0
$ export TEST_REDIS_MEMORY_URL=redis://127.0.0.1:6383/0
$ bundle exec rake
$ docker compose -f test/compose.yml down
```

## Upgrading from metacrunch-redis 1.1

| 1.1 | 5.x |
|---|---|
| `Redis.new(url: ...)` in the job file | `Connection.new(url: ...)` or `CONNECTION_PARAMS` |
| `QueueSource.new(redis, "books")` | `QueueReader.new(connection, queue: "books")` |
| `blocking_mode: true` (`BLPOP` without end) | `wait: true`, or `wait: 300` to end after a quiet time; records are written while the reader waits, and SIGTERM ends it gracefully |
| entries as Strings, parsed by a transformation | `format: :json` (default) parses; `format: :string` yields Strings |
| `QueueDestination.new(redis, "books")` | `QueueWriter.new(connection, queue: "books")` with `batch:` |
| a transformation that generates JSON | the writer does (`format: :json`) |
| a buffer transformation: 200 records in one entry | one record per entry; `batch:` and `fetch:` save the round trips |
| on maxmemory: waits 10 s and tries again | waits `pause` (1 s) and tries again; also `max_length:` |
| `save_on_close: true` (`BGSAVE`) | – (persistence is Redis's configuration: RDB, AOF) |
| redis-rb 4, ActiveSupport | redis-client |

## License

MIT; see [License.txt](License.txt).
