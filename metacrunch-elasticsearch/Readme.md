# metacrunch-elasticsearch

Elasticsearch for [metacrunch](https://github.com/ubpb/metacrunch): a source that reads the documents of an index, a
sink that writes records with bulk requests, lookups for steps, and commands that create indices, switch aliases and
clean up, for Elasticsearch 8 and 9.

```ruby
require "metacrunch/elasticsearch"

Metacrunch.job do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :index, String, required: true
    args :files, min: 1
  end

  es = Metacrunch::Elasticsearch::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.files)
  sink Metacrunch::Elasticsearch::Writer.new(es, index: params.index, id: "isbn"), batch: 1000
end
```

```
$ ELASTICSEARCH_URL=https://search.example.org:9200 metacrunch run jobs/load.rb --index books books.jsonl
```

More in [`examples/`](examples): loading and exporting, and a project that rebuilds an index behind an alias.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source. Add the `elasticsearch` client in the major version of your server:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-elasticsearch"
end

gem "elasticsearch", "~> 8.19"   # for Elasticsearch 8; "~> 9.0" for Elasticsearch 9
```

Requires Ruby 4.0, metacrunch in the same version as this gem, and the client gem
[elasticsearch](https://github.com/elastic/elasticsearch-ruby) 8 or 9. OpenSearch is not supported: the client
refuses it.

### Upgrading Elasticsearch from 8 to 9

The client 8.19 talks to Elasticsearch 8 and 9; the client 9 only to Elasticsearch 9. Update the server first, then
the client (`gem "elasticsearch", "~> 9.0"`). A client 9 against a server 8 fails at once with "the elasticsearch gem
9.x cannot talk to Elasticsearch 8.x; use gem 8.x until the server runs 9".

## Connection

```ruby
es = Metacrunch::Elasticsearch::Connection.new(url: "https://search.example.org:9200", api_key: key)
```

| Option | Default | |
|---|---|---|
| `url` | the client's: `ELASTICSEARCH_URL`, else `http://localhost:9200` | a URL, several comma-separated, or an Array |
| `api_key` | | the API key as Elasticsearch issues it (Base64 `id:key`) |
| `user`, `password` | | basic authentication; not together with `api_key` |
| `ca_file` | | the CA certificate for TLS (Elasticsearch 8 and later: `http_ca.crt`) |
| `request_timeout` | `60` | seconds |
| `retries` | `3` | retries of a request whose connection failed, on the next host |
| any other | | passed to `Elasticsearch::Client.new`, e.g. `log: true`; they win over the options above |

A connection is a value: building one sends no request. Every reader, writer, `Search` and `Indices` builds its own
client from it and checks the server on its first request: Elasticsearch, in a version the client works with.
`connection.client` returns a client of your own for anything else. `inspect` and the messages never show the API
key or the password.

The same parameters for jobs and commands, with environment variables and
[credentials](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/credentials.md):

```ruby
params do
  instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
end

es = Metacrunch::Elasticsearch::Connection.from_params(params)
```

| Param | Environment | Credential |
|---|---|---|
| `--url` | `ELASTICSEARCH_URL` | |
| `--api-key` | `ELASTICSEARCH_API_KEY` | `elasticsearch.api_key` |
| `--user` | `ELASTICSEARCH_USER` | |
| `--password` | `ELASTICSEARCH_PASSWORD` | `elasticsearch.password` |
| `--ca-file` | `ELASTICSEARCH_CA_FILE` | |

## Reading

```ruby
source Metacrunch::Elasticsearch::Reader.new(es, index: "books")                              # every document
source Metacrunch::Elasticsearch::Reader.new(es, index: "books", query: {term: {lang: "en"}})  # those a query matches
source Metacrunch::Elasticsearch::Reader.new(es, index: "books", hits: true)                  # with _index and _id
```

| Option | Default | |
|---|---|---|
| `index` | | an index, alias or pattern, or an Array of them |
| `query` | all documents | the query DSL as a Hash |
| `source` | everything | a `_source` filter: an Array of fields, or `false` (with `hits: true`) |
| `sort` | `[{_shard_doc: "asc"}]`, the fastest | any sort of the search API |
| `size` | `1000` | hits per page, up to 10 000 |
| `keep_alive` | `"5m"` | how long the point in time lives between two pages |
| `hits` | `false` | `true`: records are hits (`"_index"`, `"_id"`, `"_source"`, ...) |

Records are the documents' `_source`, Hashes with String keys. The reader opens a point in time and pages through it
with `search_after`, as Elastic recommends; a job that stops early (`--limit`, an abort) closes it. The progress
display counts the hits. A missing index stops the job with `Metacrunch::InputError`.

To re-index into another index with a change, read hits and keep the id:

```ruby
source Metacrunch::Elasticsearch::Reader.new(es, index: "books", hits: true)
map { |hit| hit["_source"].merge("id" => hit["_id"]) }
sink Metacrunch::Elasticsearch::Writer.new(es, index: "books-new", id: "id"), batch: 1000
```

### Lookups in steps

`Search` finds documents for a step, e.g. the id of a record that comes without one:

```ruby
search = Metacrunch::Elasticsearch::Search.new(es, index: "books")

map do |record|
  next record if record["id"]

  ids = search.ids({bool: {should: [{term: {isbn: record["isbn"]}}, {term: {issn: record["issn"]}}]}}, size: 2)
  ids.one? ? record.merge("id" => ids.first) : record
end
```

`ids(query, size: 10)` returns the `_id`s, `hits(query, size: 10)` the hits. Each process gets its own client, also
the workers of `-w`.

## Writing

```ruby
sink Metacrunch::Elasticsearch::Writer.new(es, index: "books", id: "isbn"), batch: 1000
sink Metacrunch::Elasticsearch::Writer.new(es, index: "books", id: "isbn",
                                               action: ->(book) { book["deleted"] ? :delete : :index }), batch: 1000
```

| Option | Default | |
|---|---|---|
| `index` | | the index, or an alias with one index or a write index |
| `id` | Elasticsearch assigns ids | a key of the record, or a callable that returns the `_id` |
| `action` | `:index` | `:index`, `:create`, `:update`, `:upsert`, `:delete`, or a callable that returns one |
| `max_bytes` | 10 MB | the upper limit of one bulk request |
| `retries` | `5` | how often a request or document that Elasticsearch refuses for now is sent again |

| Action | Bulk action | Needs an id | |
|---|---|---|---|
| `:index` | `index` | no | adds or replaces the document |
| `:create` | `create` | no | adds it; an existing id is a failure (409) |
| `:update` | `update` | yes | changes the fields of the record; a missing document is a failure (404) |
| `:upsert` | `update` with `doc_as_upsert` | yes | changes the fields, or adds the document |
| `:delete` | `delete` | yes | removes it; a missing document counts as written |

Use the writer with `batch:`: without it, every record is a request of its own. The writer cuts a batch into requests
of at most `max_bytes`; a document larger than that goes alone. The writer checks on `open` that the index exists:
Elasticsearch would create a missing one with guessed mappings.

### Failures

Elasticsearch answers a bulk request with a result per document. The writer sends again, after a growing delay (1 s,
2 s, 4 s, ... up to 60 s), what is refused for now: the request with 429, 502, 503 or 504, single documents with 429
or 5xx. When they are still refused after `retries`, the job stops: the cluster is overloaded, not the records at
fault.

Documents refused for good (a value the mappings do not take, a conflict, a missing document for `:update`) and
records that cannot be sent (no Hash, no id where the action needs one, an id longer than 512 bytes, NaN) are failed
records: the job stops by default; with `on_failure :skip` they go to the `failures` sink, with the reason in
`ctx.failure.error` (a `Metacrunch::Elasticsearch::BulkItemError` with `status`, `type` and `reason`):

```ruby
sink Metacrunch::Elasticsearch::Writer.new(es, index: "books", id: "isbn"), batch: 1000
failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")
on_failure :skip, max_failures: 100
```

```
$ metacrunch run examples/load.rb --index books examples/data/books.jsonl
15:44:56 ERROR [#4] step sink failed at position 4: Metacrunch::Elasticsearch::BulkItemError: 400 document_parsing_exception: [1:68] failed to parse field [year] of type [integer] in document with id '9780140449266'. Preview of field's value: 'around 1844' (index 9780140449266)
15:44:56 INFO  ok_with_failures: read 6, written 5, failed 1 (Metacrunch::Elasticsearch::BulkItemError: 1) in 0.05s (131 records/s)
```

The run then ends with `ok_with_failures` (exit status 3), and `stats.written` counts the documents written. Without
`id:`, a request that is sent again after a lost answer may index a document twice; give ids where that matters.

## Indices and aliases

A full load writes into a new index and switches an alias to it when the load went well, so readers of the alias
never see a half-loaded index. `Indices` has the steps; a project chains them in a command:

```ruby
Metacrunch.command "books:rebuild", desc: "Load the books into a new index and switch the alias to it" do
  params { instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS) }

  run do
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    settings = root.join("config/books.settings.jsonc")
    index = indices.create_for("books", settings:, mappings: root.join("config/books.mappings.jsonc"), bulk_load: true)
    switched = false
    begin
      result = invoke "books:load", params: {**params.to_h, index:}
      next logger.warn("books:rebuild: #{result.status}; books not switched") unless result.ok?

      indices.finish_load(index, settings:)
      indices.switch_alias("books", index)
      switched = true
    ensure
      indices.delete(index) unless switched
    end
    indices.prune("books", keep: 1)
  end
end
```

A load that refused records or aborted leaves the alias where it is, and the command deletes its index (in `ensure`,
so also after an abort): `prune` keeps indices by their names and would otherwise keep the half-loaded one as the index
to go back to.

- `create_for("books", ...)` creates `books-20261026-153000` (UTC) and returns the name; `create(name, ...)` takes a
  name of your own. Both refuse an existing index.
- `settings:` and `mappings:` are Hashes or paths of JSON files, which may have comments and trailing commas.
- `bulk_load: true` turns off refreshing and replicas while the index loads, as Elastic recommends; `finish_load`
  puts back the values of the settings (or Elasticsearch's defaults) and refreshes the index.
- `switch_alias("books", index)` points the alias to the new index alone in one atomic request, and adds the alias the
  first time. It returns the indices the alias pointed to before.
- `prune("books", keep: 1)` deletes the indices named `books-YYYYMMDD-HHMMSS` that are older than the one the alias
  points to, but the newest `keep` of them, for going back. Newer ones without the alias (a load that runs) stay;
  `dry_run: true` only logs.
- `update_settings(name, settings, reopen: true)` changes settings; `reopen:` closes the index first and opens it
  again, as analyzers need. `number_of_shards` is left out, so the settings file of `create` works here, too.
- `delete(name)` refuses an index an alias points to, unless `force: true`. `list("books*")` describes indices.

An incremental update runs the load job against the alias: `metacrunch books:load --index books changes.jsonl`.

### Commands

The gem ships the steps as commands. A project opts in:

```ruby
# Metacrunchfile
require "metacrunch/elasticsearch"

Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS, "jobs/**/*.rb", "commands/**/*.rb"
```

| Command | |
|---|---|
| `es:create-index [NAME] [--alias A] [--settings F] [--mappings F] [--bulk-load] [--skip-existing]` | creates NAME, or `A-YYYYMMDD-HHMMSS` |
| `es:finish-load INDEX [--settings F]` | puts back refreshing and replicas, refreshes |
| `es:switch-alias ALIAS INDEX` | points the alias to the index |
| `es:prune ALIAS [--keep 1] [--dry-run]` | deletes older indices of the alias |
| `es:delete-index NAME [--force]` | deletes an index no alias points to |
| `es:update-settings INDEX --settings F [--reopen]` | changes settings |
| `es:list [PATTERN]` | prints indices with aliases, documents, size and health |

All take the connection parameters (`--url`, `--api-key`, ...) and their environment variables.

## Testing jobs

`Metacrunch::Testing.run` replaces the sinks and never opens them, so a job with this writer runs in tests without
Elasticsearch; give it `source:` for a job that reads Elasticsearch:

```ruby
result = Metacrunch::Testing.run(project, "books:load", params: {index: "books", input: "test/fixtures/books.jsonl"})
assert_equal 5, result.records.size
```

## Running the tests of this gem

The unit tests need no Elasticsearch. The tests in `test/integration` run against a server when `ELASTICSEARCH_URL`
is set and are skipped otherwise. [`test/compose.yml`](test/compose.yml) starts Elasticsearch 8 and 9 with Docker:

```
$ docker compose -f test/compose.yml up -d --wait
$ export ELASTICSEARCH_USER=elastic ELASTICSEARCH_PASSWORD=metacrunch
$ ELASTICSEARCH_URL=http://localhost:9209 bundle exec rake                                    # 9, client 9
$ ELASTICSEARCH_URL=http://localhost:9208 BUNDLE_GEMFILE=gemfiles/elasticsearch_8.gemfile bundle exec rake test  # 8, client 8
$ docker compose -f test/compose.yml down
```

## Upgrading from metacrunch-elasticsearch 5.0.0

The gem for metacrunch 4.x had a scroll source and a sink for ready-made bulk actions. This one is new:

| 4.x | 5.x |
|---|---|
| `Source.new(client, search_options: {index:, body: {query:}})` | `Reader.new(connection, index:, query:)` |
| records were hits | records are `_source`; `hits: true` for hits |
| `total_hits_callback` | the progress display |
| scroll | point in time and `search_after` |
| `Destination.new(client)` with `{index: {_index:, _id:, data:}}` built in a step | `Writer.new(connection, index:, id:, action:)` |
| a buffer transformation | `batch:` |
| `result_callback` to see failed items | `failures` and `on_failure` |
| index creation in the job | `Indices`, the `es:` commands |
| `Elasticsearch::Client.new(...)` passed in | `Connection.new(...)` or `CONNECTION_PARAMS` |

## License

MIT; see [License.txt](License.txt).
