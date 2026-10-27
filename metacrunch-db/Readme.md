# metacrunch-db

Relational databases for [metacrunch](https://github.com/ubpb/metacrunch): a source that reads a table or a query and a
sink that inserts, upserts, updates or deletes rows, for SQLite, PostgreSQL, MySQL and MariaDB, on
[Sequel](https://sequel.jeremyevans.net).

```ruby
require "metacrunch/db"

Metacrunch.job do
  params do
    instance_exec(&Metacrunch::Db::CONNECTION_PARAMS)
    args :files, min: 1
  end

  db = Metacrunch::Db::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.files)
  sink Metacrunch::Db::Writer.new(db, table: "books", action: :upsert, key: "isbn"), batch: 1000
end
```

```
$ metacrunch run jobs/load.rb --url postgres://db.example.org/catalog --user etl books.jsonl
```

More in [`examples/`](examples): a project that creates a table, loads, exports and copies it.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source. Add the driver of your database:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-db"
end

gem "pg"          # PostgreSQL
gem "mysql2"      # MySQL and MariaDB; or "trilogy"
gem "sqlite3"     # SQLite
```

| Database | Gem | URL | Tested with |
|---|---|---|---|
| PostgreSQL | `pg` | `postgres://host/database` | PostgreSQL 18 |
| MySQL, MariaDB | `mysql2` (recommended) or `trilogy` | `mysql2://host/database`, `trilogy://host/database` | MySQL 8.4, MariaDB 11.8 |
| SQLite | `sqlite3` | `sqlite://path/to/file.db`, `sqlite:///absolute/path.db` | SQLite 3 of sqlite3 2.x |

Requires Ruby 4.0, metacrunch in the same version as this gem, and Sequel 5. `pg` and `sqlite3` come precompiled;
`mysql2` needs the MySQL client library (`libmysqlclient-dev`, or MariaDB Connector/C), `trilogy` only OpenSSL. Other
databases Sequel has an adapter for (Oracle with `ruby-oci8`, SQL Server with `tiny_tds`, ...) should work for
reading and for insert, update and delete, but are not tested; upsert needs one of the four above.

## Connection

```ruby
db = Metacrunch::Db::Connection.new(url: "postgres://db.example.org/catalog", user: "etl", password: password)
db = Metacrunch::Db::Connection.new(url: "sqlite://#{root.join("data/books.db")}")
```

| Option | | |
|---|---|---|
| `url` | required | a [Sequel URL](https://sequel.jeremyevans.net/rdoc/files/doc/opening_databases_rdoc.html); `user:password@` in it counts as `user` and `password` |
| `user`, `password` | | the login; not together with user info in the URL |
| any other | | passed to `Sequel.connect`, e.g. `max_connections:`, `connect_timeout:`, `sslmode:`, `search_path:`, `encoding:`, `extensions:` |

A connection is a value: building one connects nowhere and loads no driver, so `--help`, `check` and
`Metacrunch::Testing` need no database. Every reader and writer opens a database of its own from it when the job
opens it, and disconnects when the job closes it; `connect` checks the connection at once, so a wrong host or
password stops the job before the first record. A missing driver says which gem to add ("the adapter postgres needs
the gem pg; add it to the Gemfile"). `inspect` and the messages never show the password. An in-memory SQLite
database (`sqlite::memory:`) is refused: it lives in one connection, and every component opens its own.

`connection.connect` returns a `Sequel::Database` of your own, and with a block disconnects it afterwards, e.g. in a
command:

```ruby
Metacrunch::Db::Connection.from_params(params).connect do |db|
  db.create_table?(:books) { String :isbn, primary_key: true; String :title }
end
```

The same parameters for jobs and commands: `--url`, `--user` and `--password`. The password is a
[secret](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#secrets), hidden in `--help`, messages
and `inspect`. A [params file](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/jobs.md#parameter-files)
gives them per [environment](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/environments.md), the
password from an environment variable or the
[credentials](https://github.com/ubpb/metacrunch/blob/master/metacrunch/docs/credentials.md). Give it apart from the
URL: `url` is a plain parameter, which messages may show.

```yaml
# params.yml
default:
  url: sqlite://books.db

production:
  url: postgres://db.example.org/catalog
  user: etl
  password: {credential: db.password}
```

```
$ metacrunch run -e production --params params.yml books:load
```

A job with two databases declares the parameters with a prefix each:

```ruby
params do
  instance_exec(&Metacrunch::Db.connection_params("source"))   # --source-url, --source-user, --source-password
  instance_exec(&Metacrunch::Db.connection_params("target"))   # --target-url, ...
end

source Metacrunch::Db::Reader.new(Metacrunch::Db::Connection.from_params(params, prefix: "source"), table: "books")
sink Metacrunch::Db::Writer.new(Metacrunch::Db::Connection.from_params(params, prefix: "target"), table: "books"),
     batch: 1000
```

## Reading

```ruby
source Metacrunch::Db::Reader.new(db, table: "books")
source Metacrunch::Db::Reader.new(db, query: "SELECT isbn, title FROM books WHERE lang = :lang", values: {lang: "en"})
source Metacrunch::Db::Reader.new(db, query: "SELECT * FROM books WHERE year > ? AND lang = ?", values: [1900, "en"])
source Metacrunch::Db::Reader.new(db, query: ->(db) { db[:books].where(lang: "en").select(:isbn, :title) })
```

| Option | Default | |
|---|---|---|
| `table` | | a table, `"books"`, or with its schema `"library.books"` (on MySQL and MariaDB: its database) |
| `query` | | SQL, or a callable that gets the `Sequel::Database` and returns a [dataset](https://sequel.jeremyevans.net/rdoc/files/doc/querying_rdoc.html) |
| `values` | | the values of the placeholders of a SQL query: a Hash for `:name`, an Array for `?` |
| `count` | `false` | `true`: count the rows first, with one more query, for the progress display |
| `idle_timeout` | `3600` | seconds the database may wait for the job between two rows |

Give `table` or `query`. Put values into a query with `values:` or a dataset, never into the SQL String: Sequel quotes
them. Records are the rows as Hashes with String keys, as everywhere in metacrunch. A result with a column name twice
(`SELECT a.id, b.id ...`) stops the job before the first record, since one key would be lost: name the columns apart
(`AS`).

The reader runs one query and streams its result, so any query works, without an order, memory stays flat and the
rows are one consistent snapshot:

| Database, driver | How |
|---|---|
| PostgreSQL, `pg` | a cursor in a transaction, 1000 rows per fetch |
| MySQL, MariaDB, `mysql2` | the result streamed by the driver |
| SQLite | the statement steps through the result |
| `trilogy` and other drivers | the driver may read the whole result into memory: use `mysql2` for large results |

A job that pauses between two rows, e.g. while a sink waits, must not lose the stream: the reader sets the limit of
its session to `idle_timeout` (MySQL's `net_write_timeout`, 60 s by default; PostgreSQL's
`idle_in_transaction_session_timeout`). A job that stops early (`--limit`, an abort) ends the cursor and its
transaction; with `mysql2` the driver still reads the rest of the result first (about a second per million small
rows), which a `LIMIT` in the query avoids.

### Values

Values are Sequel's Ruby types: Integer, Float, BigDecimal (NUMERIC, DECIMAL), String, Date, Time (TIMESTAMP,
DATETIME, in local time), `Sequel::SQLTime` (TIME), true and false (BOOLEAN; TINYINT(1) on MySQL), `Sequel::SQL::Blob`
(BLOB, BYTEA), nil. JSON columns and PostgreSQL arrays come as Strings. A copy into another database keeps the
types; JSON Lines has no dates and no decimals, and CSV and Excel no dates, so a step turns them into text:

```ruby
map do |book|
  book.transform_values do |value|
    case value
    when Date, Time then value.iso8601
    when BigDecimal then value.to_s("F")
    else value
    end
  end
end
map { it.merge("data" => JSON.parse(it["data"])) }   # a JSON column
```

## Writing

```ruby
sink Metacrunch::Db::Writer.new(db, table: "books"), batch: 1000
sink Metacrunch::Db::Writer.new(db, table: "books", action: :upsert, key: "isbn"), batch: 1000
sink Metacrunch::Db::Writer.new(db, table: "books", key: "isbn",
                                    action: ->(book) { book["deleted"] ? :delete : :upsert }), batch: 1000
```

| Option | Default | |
|---|---|---|
| `table` | | the table, as for the reader |
| `action` | `:insert` | `:insert`, `:upsert`, `:update`, `:delete`, or a callable that returns one per record |
| `key` | | the column, or an Array of columns, that identifies a row; needed for every action but `:insert` |
| `max_bytes` | 1 MB | the upper limit of the values of one statement |

| Action | SQL | |
|---|---|---|
| `:insert` | `INSERT` | adds the row; an existing key is a failure |
| `:upsert` | `INSERT ... ON CONFLICT DO UPDATE` (PostgreSQL, SQLite), `ON DUPLICATE KEY UPDATE` (MySQL, MariaDB) | adds the row, or sets the record's other columns; the key must be the primary key or a unique index |
| `:update` | `UPDATE ... WHERE key` | sets the record's other columns; no row with the key is a failure |
| `:delete` | `DELETE ... WHERE key IN (...)` | removes the row; a missing row counts as written; only the key columns of the record are used |

A record is a Hash whose keys are the columns, Strings or Symbols, matched as written (`"Title"` is not `title`);
columns it leaves out keep their default. Values are Strings, numbers (Integer, Float, BigDecimal), true and false,
nil, Date and Time, or Sequel's own objects (`Sequel.lit`, `Sequel.pg_array`, ...). Hashes and Arrays are not:
Sequel would write a Hash as a condition and an Array as a list, so a JSON column takes `JSON.generate(value)`. A
record with a column the table lacks, without a value for the key, or with another value is a failure with a message
such as `books has no column titel`, before any SQL.

When the writer opens, it checks that the table exists, has the key columns and, for `:upsert`, that the key is unique
and the database can upsert. The table must exist: create it with a migration, or in a command as in the examples.

### Batches, transactions and failures

Use the writer with `batch:`: without it, every record is a transaction of its own. A batch is one transaction. Within
it, consecutive records with the same action and columns go into one statement each (a multi-row `INSERT`, a `DELETE
... IN`; updates one per row) of at most `max_bytes`, so a batch of large texts stays under MySQL's
`max_allowed_packet` (16 MB on MariaDB). The order of the batch holds; an upsert batch with a key twice keeps the last
record.

A row the database refuses (a duplicate key, a NULL for a NOT NULL column, a text too long, a value the column does
not take) does not stop the batch: the writer runs each statement in a savepoint, and when one fails, its records
again one by one, so only the refused ones fail. They are failed records, with Sequel's error in `ctx.failure.error`
(`Sequel::UniqueConstraintViolation`, `Sequel::NotNullConstraintViolation`, `Sequel::DatabaseError`, ...): the job
stops by default; with `on_failure :skip` they go to the `failures` sink and the others are written:

```ruby
sink Metacrunch::Db::Writer.new(db, table: "books", action: :upsert, key: "isbn"), batch: 1000
failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")
on_failure :skip, max_failures: 100
```

```
$ metacrunch run --params params.yml books:load     # in examples/
20:17:13 ERROR [9780199535569] step sink failed at position 4 (id 9780199535569): Sequel::NotNullConstraintViolation: SQLite3::ConstraintException: NOT NULL constraint failed: books.title
20:17:13 INFO  ok_with_failures: read 6, written 5, failed 1 (Sequel::NotNullConstraintViolation: 1) in 0.01s (452 records/s)
```

The run then ends with `ok_with_failures` (exit status 3), and `stats.written` counts the records written. A broken
connection, a deadlock or a lock timeout stops the run, and the batch's transaction is rolled back. A batch that has
failed records is committed before the failure policy acts: a load that must be all or nothing writes into a table
of its own and swaps it in a command afterwards.

## Lookups in steps

A step that queries a database opens its own, so each worker of `-w` has one:

```ruby
class Authors
  def initialize(connection) = @connection = connection
  def open(_context) = @db = @connection.connect
  def call(book) = book.merge("authors" => @db[:authors].where(isbn: book["isbn"]).select_map(:name))
  def close = @db&.disconnect
end

map Authors.new(db)
```

## Workers and SQLite

With `-w`, the workers inherit the connections of the reader and the writer, which only the main process uses. The
`sqlite3` gem warns about each inherited writable connection in every worker. The warning is harmless here; silence
it in the job file with `SQLite3::ForkSafety.suppress_warnings!`.

## Testing jobs

`Metacrunch::Testing.run` replaces the source and the sinks and opens neither, so a job with this reader or writer runs
in tests without a database. The connection parameters still need a value, a URL with a scheme:

```ruby
result = Metacrunch::Testing.run(PROJECT, "books:load", params: {url: "sqlite://unused.db"}, source: books)
```

## Running the tests of this gem

The unit tests and the integration tests against SQLite need no server. Those against PostgreSQL, MySQL and MariaDB
run when the URLs are set and are skipped otherwise; PostgreSQL runs with the Gemfile, MySQL and MariaDB with
`gemfiles/mysql.gemfile` (mysql2 and trilogy). [`test/compose.yml`](test/compose.yml) starts the servers with
Docker:

```
$ docker compose -f test/compose.yml up -d --wait
$ export TEST_POSTGRES_URL=postgres://postgres:metacrunch@127.0.0.1:5433/metacrunch
$ export TEST_MYSQL_URL=mysql://root:metacrunch@127.0.0.1:3307/metacrunch
$ export TEST_MARIADB_URL=mysql://root:metacrunch@127.0.0.1:3308/metacrunch
$ bundle exec rake
$ BUNDLE_GEMFILE=gemfiles/mysql.gemfile bundle exec rake test
$ docker compose -f test/compose.yml down
```

## Upgrading from metacrunch-db 1.0

| 1.0 | 5.x |
|---|---|
| `Sequel.connect(...)` in the job file | `Connection.new(...)` or `CONNECTION_PARAMS` |
| `Source.new(DB[:books].order(:id), rows_per_fetch: 1000)` | `Reader.new(connection, table: "books")` |
| a dataset that must be ordered, read with `paged_each` | any query or dataset (`query: ->(db) { ... }`), streamed |
| Symbol keys | String keys |
| `Destination.new(DB[:books])` | `Writer.new(connection, table: "books")` |
| `use_upsert: true, primary_key: :id`: update, else insert, per record | `action: :upsert, key: "id"`: one statement per batch |
| a buffer transformation, an Array per `write` | `batch:` |
| `transaction_options:` | one transaction per batch |
| a refused row stops the job | a failed record, for the failure policy |
| ActiveSupport | – |

## License

MIT; see [License.txt](License.txt).
