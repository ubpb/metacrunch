# Changelog

## 5.1.0 (unreleased)

The first version for metacrunch 5, for Elasticsearch 8 and 9. It replaces metacrunch-elasticsearch 5.0.0, which
belongs to metacrunch 4.x.

It lives in the metacrunch repository, shares metacrunch's version and requires metacrunch in exactly that version.

### Added

- `Metacrunch::Elasticsearch::Connection`: URL(s), API key or user and password, CA file, timeout and retries, and
  any option of the client; a check of the server on the first request (Elasticsearch, a version the client works
  with); `CONNECTION_PARAMS`, a group of parameters (`params { use ... }`; the API key and the password as secrets),
  and `Connection.from_params` for jobs and commands.
- `Metacrunch::Elasticsearch::Reader`, a source: the documents of an index, alias or pattern, or those a query
  matches, read with a point in time and `search_after`; `_source` or hits as records; progress.
- `Metacrunch::Elasticsearch::Search`: `ids` and `hits` for lookups in steps.
- `Metacrunch::Elasticsearch::Writer`, a bulk sink: `index`, `create`, `update`, `upsert` and `delete` per record,
  the `_id` from a key or a callable, requests of at most `max_bytes`, retries of what Elasticsearch refuses for now,
  and the documents it refuses for good as failed records (`Metacrunch::SinkFailures`).
- `Metacrunch::Elasticsearch::Indices`: `create`, `create_for` (an index named after an alias and the time),
  `finish_load`, `switch_alias`, `prune`, `update_settings`, `delete`, `list`; settings and mappings from JSON files
  with comments.
- The commands `es:create-index`, `es:finish-load`, `es:switch-alias`, `es:prune`, `es:delete-index`,
  `es:update-settings` and `es:list`, which a project loads with `Metacrunch::Elasticsearch::COMMANDS`.
- Vectors: the Readme shows `dense_vector` fields filled by metacrunch-ai, reading vectors back from 9.2
  (`source: {exclude_vectors: false}`), `knn` lookups with `Search`, and `semantic_text` as an alternative;
  integration tests cover them on Elasticsearch 8 and 9.
- Chunk indices: the Readme shows a mapping for metacrunch-ai's chunk records and a `knn` search that keeps the best
  passage per document with `collapse` on `parent_id`; an integration test covers it on Elasticsearch 8 and 9.

### Changes from metacrunch-elasticsearch 5.0.0

- `Source` and `Destination` are replaced by `Reader` and `Writer`, which take a `Connection` instead of a client.
- The reader yields `_source`, or hits with `hits: true`, and reads with a point in time instead of scroll.
- The writer builds the bulk actions itself (`id:`, `action:`), batches with `batch:`, and reports failed documents
  instead of passing the response to a callback.
- No dependency on ActiveSupport.
