# 5. Steps can take records in batches

- Status: accepted
- Date: 2026-11-02

## Context

Steps ran one record at a time: the processor pushes each record through a chain of steps. Many services answer for
many records per request and charge or throttle per request: embedding APIs take hundreds of texts at once, local
embedding servers reach their throughput only with batches, and lookups in a database or a search index are cheaper
as one `IN (...)` query or `mget` than as one query per record. Embedding a million records one request at a time
takes more than five hours at 3,000 requests per minute; with 100 texts per request it takes minutes. Sinks already
take batches (`batch:`), but a sink comes last and runs only in the main process.

## Decision

`map`, `filter`, `reject` and `flat_map` take `batch: N`. Such a step keeps the records that reach it and calls its
batch function (a block, or an object's `call_batch`) with up to N records, and their contexts if it asks for them.
The function returns one result per record, in order, and the engine applies each as it applies the result of a step
without `batch:`. An Exception in the results fails its record; a raising function fails the whole batch.
`ctx.reject!`, which would end the call for every record of the batch, breaks the contract there.

Both executors cut the records into the same segments and run the batch steps on what they hold at the end of each
segment, at a `FLUSH` and at the end of the source. With workers a segment is a transport batch; inline it is as many
records. The segment is the smallest multiple of the largest `batch:` that is at least 100, so that step gets full
batches.

## Alternatives

- A sink that embeds a batch before it writes: no change to the engine, but it runs only in the main process,
  only at the end of a job, and not in transforms; a sink would change records.
- One request per record, made parallel with workers: too slow and too expensive for real data, as above.
- Full source order in every sink: a reorder buffer that holds rejected and failed records and log lines back until
  the records before them left the batch steps. It is the largest component of the engine, and log lines inline can
  hardly be held back.
- Batches cut differently inline and in workers: the `rejects` and `failures` sinks and the stop under
  `max_failures` would then differ with and without workers, which the engine promised to avoid.

## Consequences

- The sink gets its records in source order. The `rejects` and `failures` sinks and the log get them in the order
  they leave the steps: a record that waits in a batch step arrives after later records an earlier step rejected.
  The order is the same with and without workers.
- Records a batch step holds when a job aborts are dropped, neither written nor counted as failed.
- A job with large batches sends larger transport batches to its workers and holds up to one per batch step.
- `trace` gives batch steps batches of one record, so it still shows one record at a time.
- Per-record rejection inside a batch function is left for later; `filter` and `reject` with a reason do it.
