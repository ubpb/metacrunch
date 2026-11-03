# Changelog

## 5.1.0 (unreleased)

The first version, for metacrunch 5.

It lives in the metacrunch repository, shares metacrunch's version and requires metacrunch in exactly that version.

### Added

- `Metacrunch::Ai::Embed`, a step that adds a vector per record from a field, several fields or a callable; with
  `batch:` it sends a batch's texts in as few requests as the service takes. It probes the service when it opens, so
  a wrong key, model or URL stops the job before records are read; isolates the texts a service refuses; leaves
  records without text unchanged, with a mark; logs texts, calls and tokens when it closes.
- `Metacrunch::Ai::OpenAi`, an embedder for the OpenAI embeddings API and the servers that offer it (Azure OpenAI,
  Voyage AI, Mistral, Hugging Face Text Embeddings Inference, Ollama, vLLM), with further headers and request fields,
  `max_inputs`, timeouts and retries with a growing delay and `Retry-After`, over one persistent connection per
  process, with Ruby's `net/http`.
- `Metacrunch::Ai::EMBEDDINGS_PARAMS`, a group of parameters (`embeddings_url`, `embeddings_model`, the secret
  `embeddings_api_key`), and `Metacrunch::Ai.embedder(params)`.
- `Metacrunch::Ai::FakeEmbedder`, deterministic unit vectors without network, for tests and dry runs:
  `embeddings_url` `fake` or `fake:DIMS`.
- Errors `Metacrunch::Ai::InvalidInput`, `Unavailable` and `ApiError` with the HTTP status and an excerpt of the
  answer.
- `Metacrunch::Ai::Extract`, a step that turns a document's content into Markdown text with exchangeable extractors,
  chosen by MIME type: `Html` (the main content of a page, in Ruby with Nokogiri, the gem's new dependency), `Text`
  (plain text and Markdown as they are, with YAML front matter as fields and page markers as pages) and `Tika` (PDF,
  office and many other formats through an Apache Tika server, a PDF's text page by page), with
  `Metacrunch::Ai::TIKA_PARAMS` and `Metacrunch::Ai.tika(params)`. It writes title, language and further fields an
  extractor gives, drops the raw content, and marks documents without text.
- `Metacrunch::Ai::Chunk`, a step for `flat_map` that cuts a document's text into chunk records by its structure,
  recursively, with `size`, `overlap` and an optional length function such as a tokenizer; each chunk has the id of
  its document, its number, its heading path and its pages.
- `Metacrunch::Ai::Fetch`, a step that downloads the document whose URL a record holds and adds the fields of a file
  record, politely: a user agent, a delay per host, robots.txt (RFC 9309) with `Crawl-delay`, a bounded number of
  redirects and a size limit; dead and refused links pass with a mark. It follows no links.
- `Metacrunch::Ai::Sitemap::Reader`, a source of the pages a website lists in its sitemaps, with sitemap indexes,
  gzip, discovery through robots.txt and filters by URL and date.
