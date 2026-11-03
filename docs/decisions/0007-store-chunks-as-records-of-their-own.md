# 7. Store chunks as records of their own

- Status: accepted
- Date: 2026-11-03

## Context

Long documents (web pages, PDFs, office files) are cut into chunks before they are embedded: a vector stands for a
passage of a few hundred tokens, and a search finds the passage, not only the document. A chunk needs the id of its
document, its number, its heading path and its pages, so that an answer can name its source.

There are two ways to store chunks. Most tools (LangChain, LlamaIndex, Haystack, Unstructured, Airbyte, Redpanda
Connect) store each chunk as a record of its own, with the document's id in a field, in whatever store they write to.
Elasticsearch and OpenSearch can also keep one record per document with its chunks in a nested field, each with its
vector; a kNN query on the nested field returns the document with its best passages, and Elasticsearch's
`semantic_text` field does the same internally.

metacrunch's `Embed` step gives one vector per record, and its sinks write records to Elasticsearch, databases and
Redis alike.

## Decision

A chunk is a record of its own. The step `Metacrunch::Ai::Chunk` turns a document into chunk records with `flat_map`:
`id` (`"#{parent_id}##{n}"`), `parent_id`, `chunk` (the number, from 1), `headings`, `pages` and the chunk's text,
over the document's fields. `Embed` embeds them as any other record. The chunker itself is also a plain function,
`Chunk#split`, which returns the chunks of a text.

## Alternatives

- One record per document with nested chunks and vectors: when a document changes, writing it again replaces all its
  chunks, so no chunk is left behind. But only Elasticsearch and OpenSearch support it; pgvector, Qdrant or Redis
  would need a different shape; and `Embed` would have to embed many texts inside one record. It can be added later
  on top of `Chunk#split`.
- `semantic_text` in Elasticsearch: the store chunks and embeds by itself; for services other than Elastic's own it
  needs a license on a self-managed cluster, and the chunking is no longer metacrunch's to control or test.

## Consequences

- Every vector store that metacrunch writes to can take chunks, with the same jobs.
- When a document changes or disappears, its old chunks must be removed: by rebuilding the index and switching an
  alias (which metacrunch-elasticsearch supports), or, later, by deleting the chunks of a `parent_id` before writing
  the new ones. Chunks carry `parent_id` and the document's fields (such as a hash) for that.
- A search over chunks returns several hits per document; collapsing them by `parent_id` is the query's job.
