# Changelog

## 5.1.0 (unreleased)

The first version for metacrunch 5, for SQLite, PostgreSQL, MySQL and MariaDB on Sequel 5. It replaces
metacrunch-db 1.0.1, which belongs to metacrunch 4.x.

It lives in the metacrunch repository, shares metacrunch's version and requires metacrunch in exactly that version.

### Added

- `Metacrunch::Db::Connection`: a Sequel URL, user and password, and any option of `Sequel.connect`; a database of
  its own for every reader and writer, checked when it opens; the gem to add when a driver is missing;
  `CONNECTION_PARAMS` (the password as a secret), `Metacrunch::Db.connection_params(prefix)` for jobs with two
  databases, and `Connection.from_params` for jobs and commands.
- `Metacrunch::Db::Reader`, a source: a table, SQL with placeholders or a Sequel dataset, read with one query and
  streamed (a cursor on PostgreSQL, a stream on mysql2); records with String keys; `count:` for progress; the
  session's idle limit raised, so a pause in the job does not end the stream; a result with a column name twice is
  refused.
- `Metacrunch::Db::Writer`, a sink: `insert`, `upsert` (`ON CONFLICT`, `ON DUPLICATE KEY UPDATE`), `update` and
  `delete` per record by a key of one or more columns, one transaction per batch, statements of at most
  `max_bytes`; checks of the table when it opens and of every record before any SQL; rows the database refuses
  isolated with savepoints and reported as failed records (`Metacrunch::SinkFailures`).

### Changes from metacrunch-db 1.0

- `Source` and `Destination` are replaced by `Reader` and `Writer`, which take a `Connection` instead of a Sequel
  dataset.
- The reader streams any query instead of paging an ordered dataset with `paged_each`, and yields String keys.
- The writer upserts with one statement per batch instead of an update, else an insert, per record, batches with
  `batch:` instead of a buffer transformation, and reports refused rows as failed records instead of stopping.
- No dependency on ActiveSupport.
