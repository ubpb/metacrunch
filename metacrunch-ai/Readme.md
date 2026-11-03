# metacrunch-ai

AI steps for [metacrunch](https://github.com/ubpb/metacrunch): a step that adds a vector to each record, through the
OpenAI embeddings API and the many servers that offer it, hosted or on your own machine, and steps that get the text
out of web pages, PDFs and office files and cut it into chunks. The vectors go wherever metacrunch writes, for example
into an Elasticsearch index for semantic or hybrid search.

```ruby
require "metacrunch/ai"
require "metacrunch/elasticsearch"

Metacrunch.job do
  params do
    use Metacrunch::Ai::EMBEDDINGS_PARAMS            # --embeddings-url, --embeddings-model, --embeddings-api-key
    use Metacrunch::Elasticsearch::CONNECTION_PARAMS
    args :files, min: 1
  end

  source Metacrunch::JsonLines::Reader.new(params.files), id: ->(book) { book["isbn"] }
  map Metacrunch::Ai::Embed.new(Metacrunch::Ai.embedder(params), text: ["title", "abstract"]), batch: 100
  sink Metacrunch::Elasticsearch::Writer.new(Metacrunch::Elasticsearch::Connection.from_params(params),
                                             index: "books", id: "isbn"), batch: 500
end
```

```
$ metacrunch run -w 4 jobs/embed.rb --embeddings-model text-embedding-3-small --url https://es.example.org:9200 \
    books.jsonl
```

The API key comes from a params file, the credentials or the environment, as any secret (see metacrunch's
[credentials](../metacrunch/docs/credentials.md)). [`examples/embed.rb`](examples/embed.rb) embeds books from JSON
Lines into JSON Lines; [`examples/documents.rb`](examples/documents.rb) turns a directory of documents into chunks
with vectors (see [From documents to a RAG index](#from-documents-to-a-rag-index)).

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-ai"
end
```

Besides metacrunch the gem needs [Nokogiri](https://nokogiri.org), for HTML; it talks to the services with Ruby's
`net/http`. PDF and office files need an [Apache Tika](https://tika.apache.org) server.

## The Embed step

```ruby
map Metacrunch::Ai::Embed.new(embedder, text: "title"), batch: 100
map Metacrunch::Ai::Embed.new(embedder, text: ["title", "subjects"], into: "title_vector"), batch: 100
map Metacrunch::Ai::Embed.new(embedder, text: ->(book) { "#{book["title"]} (#{book["year"]})" }), batch: 100
```

| Option | Default | |
|---|---|---|
| `text` | | a field, an Array of fields, or a callable that returns the text of a record, or `nil` |
| `into` | `"embedding"` | the field that gets the vector, an Array of Floats |

- Fields of an Array join their values with line breaks; a field that holds an Array adds its elements; `nil` and
  blank values are left out, other values become Strings. These forms need Hash records.
- A record without text passes unchanged, with the mark "No text to embed", and costs no request.
- Use the step with [`batch:`](../metacrunch/docs/jobs.md#batch-steps): it then sends the texts of a batch in as few
  requests as the service takes (`max_inputs` per request). Without `batch:` every record is a request of its own.
- When it opens, the step embeds one short text. A wrong key, model or URL stops the job before it reads a record,
  and the answer tells the dimension of the vectors; a later vector of another dimension fails its record.
- When it closes, it logs what it sent, per process, with the tokens the service reported:
  `embedded 9950 texts in 312 calls, 1204331 tokens`.

## Embedders

An embedder turns texts into vectors. `Metacrunch::Ai::OpenAi` speaks the OpenAI embeddings API
(`POST {url}/embeddings`), which these services and servers offer:

| Service or server | `url` | Notes |
|---|---|---|
| OpenAI | the default, `https://api.openai.com/v1` | `api_key:`; `body: {dimensions: 256}` shortens `text-embedding-3` vectors |
| Azure OpenAI | `https://RESOURCE.openai.azure.com/openai/v1` | the key in `headers: {"api-key" => key}` |
| Voyage AI | `https://api.voyageai.com/v1` | `body: {input_type: "document"}`, and `"query"` for search queries |
| Mistral | `https://api.mistral.ai/v1` | |
| Hugging Face Text Embeddings Inference | `http://localhost:8080/v1` | its default limit is 32 texts per request |
| Ollama | `http://localhost:11434/v1` | `ollama pull` the model first |
| vLLM | `http://localhost:8000/v1` | |

```ruby
embedder = Metacrunch::Ai::OpenAi.new(model: "text-embedding-3-small", api_key: params.api_key)
embedder = Metacrunch::Ai::OpenAi.new(model: "bge-m3", url: "http://localhost:11434/v1")
```

| Option | Default | |
|---|---|---|
| `model` | | required |
| `url` | `"https://api.openai.com/v1"` | the API base; `/embeddings` is added, a query is kept |
| `api_key` | | sent as `Authorization: Bearer` |
| `headers` | `{}` | further headers |
| `body` | `{}` | further fields of the request |
| `max_inputs` | `32` | texts per request; OpenAI takes 2048, other services less |
| `timeout` | `60` | seconds to connect, send and wait for an answer |
| `retries` | `5` | how often a request is sent again that the service refused for now |

Some models want a prefix that says what a text is, such as `search_document: ` or `passage: `; add it in `text:`
with a callable.

### Params

Jobs and commands take the embedder from params, as the other gems take their connections:

```ruby
params { use Metacrunch::Ai::EMBEDDINGS_PARAMS }
embedder = Metacrunch::Ai.embedder(params, max_inputs: 64)    # further options of OpenAi.new
```

`EMBEDDINGS_PARAMS` declares `embeddings_url`, `embeddings_model` and the secret `embeddings_api_key`. The prefix keeps
them apart from the `url` and `api_key` of the other gems, so a job can use both groups.

### Other embedders

Any object with `embed(texts)` that returns one vector (an Array of numbers) per text, in the order of the texts, is
an embedder. It may have `open(context)`, `close`, `max_inputs` and `stats` (a Hash; `"tokens"` goes into the log
line). Libraries with providers of their own fit in a few lines, for example [ruby_llm](https://rubyllm.com):

```ruby
class RubyLlmEmbedder
  def initialize(model) = @model = model
  def max_inputs = 100
  def embed(texts) = RubyLLM.embed(texts, model: @model).vectors
end
```

## Errors and retries

- The service refuses the input of a request (HTTP 400, 413, 422), for example a text longer than the model takes:
  the step sends the texts of that request again one by one, and only the records it refuses fail, with
  `Metacrunch::Ai::InvalidInput`.
- The service is overloaded or away (429, 500, 502, 503, 504, timeouts, lost connections, garbled answers, TLS
  errors): the request goes again after 1, 2, 4, … up to 60 seconds, each cut by a random amount of up to half so
  that processes do not retry in step, or after the time `Retry-After` names, at most 60 seconds. If it still fails
  after `retries`, the records of the request fail with `Metacrunch::Ai::Unavailable`, whose message gives the last
  answer or error. A certificate the client does not trust is a TLS error too, so it stops a job only after the
  retries.
- Other refusals (a wrong key or model, 401, 403, 404) fail the records with `Metacrunch::Ai::ApiError`; when the step
  opens, they stop the job.

Failed records follow the job's failure policy. With `on_failure :skip` they go to the `failures` sink, from where
they can be fed again:

```ruby
failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")
on_failure :skip, max_failures: 1000
```

## Workers, rate limits and costs

- With `-w N` the step runs in N processes, so N requests run at once. Services limit requests and tokens per minute:
  choose N below the limit, and `batch:` large enough to use few requests. The step reacts to a 429 by waiting; it does
  not throttle ahead.
- Hosted services charge per token. The log line at the end names the tokens per process; a dry run with the fake
  embedder (below) checks a job before it costs anything.
- A new model gives vectors of another kind, which do not mix with the old ones: embed everything again into a new
  index and switch to it, as [metacrunch-elasticsearch](../metacrunch-elasticsearch#indices-and-aliases) does with
  aliases.

## Testing jobs and dry runs

`embeddings_url` `fake`, or `fake:DIMS` for vectors of DIMS numbers (8 by default), gives
`Metacrunch::Ai::FakeEmbedder`: deterministic unit vectors from the text, without network. A job that takes its
embedder from params runs in tests without a service:

```ruby
result = Metacrunch::Testing.run(job, params: {embeddings_url: "fake"}, source: books)
```

The same runs a job end to end without cost, for example to check the mappings of an index:

```
$ metacrunch run jobs/embed.rb --embeddings-url fake:1024 --url https://es.example.org:9200 books.jsonl
```

## Extracting text

```ruby
map Metacrunch::Ai::Extract.new(Metacrunch::Ai::Html.new(content: "main"), Metacrunch::Ai::Text.new,
                                Metacrunch::Ai.tika(params))
# before: {"id" => "handbook/loans.html", "type" => "text/html", "content" => "<!doctype html>…", …}
# after:  {"id" => "handbook/loans.html", "type" => "text/html", "title" => "Loans", "lang" => "en",
#          "text" => "# Loans\n\nBooks can be borrowed for four weeks.…", …}
```

The step takes a document's content (bytes or a String) from a field and its MIME type from another, as
`Metacrunch::FileList::Reader` yields them (see metacrunch's [jobs](../metacrunch/docs/jobs.md#sources)), asks the
first extractor that takes the type, and writes the text as Markdown: headings, paragraphs, lists, tables and code
blocks keep their structure, which the [chunker](#chunking) uses; links give their text only.

| Option | Default | |
|---|---|---|
| `from` | `"content"` | the field with the content; the step removes it, so the bytes are not copied into every chunk |
| `type` | `"type"` | the field with the MIME type; parameters such as `; charset=…` do not matter |
| `into` | `"text"` | the field that gets the text: a String, or an Array of Strings, one per page |
| `title`, `lang` | `"title"`, `"lang"` | the fields that get the title and language the document names; `nil` turns one off |

- A record without type goes to the first extractor; a type no extractor takes fails the record.
- A record without content or text passes with the mark "No text extracted", typically a scanned PDF without OCR.
- An error of an extractor fails its record only, under the job's failure policy; a found title or language replaces
  an existing value, a missing one keeps it.

### Html

`Metacrunch::Ai::Html.new(content: nil, remove: nil)` takes `text/html` and `application/xhtml+xml`. The main content
is the elements that the CSS selector `content:` matches, the most reliable choice for a website with a template;
without it, or when it matches nothing, the first of `<main>`, `[role=main]`, a single `<article>` and `<body>`.
Inside it, scripts, styles, `nav`, forms, frames, SVG and hidden elements are removed, with `<body>` also `header`,
`footer` and `aside`; `remove:` names more, e.g. `remove: ".cookie-banner, .breadcrumb"`. The title comes from
`<title>` or else the first `<h1>`, the language from `<html lang>`, the charset from a byte order mark or
`<meta charset>`.

### Text

`Metacrunch::Ai::Text.new` takes `text/plain` and `text/markdown` and passes the content as it is, as UTF-8 with LF
line ends; UTF-16 files with a byte order mark are converted. Markdown keeps its headings this way; Tika would read it
as plain text.

### Tika

`Metacrunch::Ai::Tika` sends PDF, office (Word, Excel, PowerPoint, OpenDocument) and many other formats to an
[Apache Tika](https://tika.apache.org) server and turns its answer into Markdown: a PDF's text page by page, an office
file's with its headings. Embedded files such as attachments are skipped.

```ruby
params { use Metacrunch::Ai::TIKA_PARAMS }          # --tika-url
tika = Metacrunch::Ai.tika(params)                  # or Metacrunch::Ai::Tika.new(url: "http://localhost:9998")
```

```
$ docker run -d -p 9998:9998 apache/tika:3.3.1.0
```

| Option | Default | |
|---|---|---|
| `url` | | the server, required |
| `headers` | `{}` | further headers, e.g. Tika's settings such as `X-Tika-PDFOcrStrategy` |
| `timeout` | `300` | seconds to connect, send and wait; large PDFs take long |
| `retries` | `2` | how often a request is sent again that the server refused for now |

- When it opens, it asks the server for its greeting, so a wrong URL stops the job before it reads a record.
- Tika answers also for files it cannot parse. Without text the record fails with `Metacrunch::Ai::InvalidInput`
  ("document is encrypted", or the first line of Tika's error); with text it passes with the mark "Text partly
  extracted". A type Tika has no parser for (HTTP 415) fails the record with `InvalidInput` too.
- Busy or failing servers are retried as [the embedders](#errors-and-retries) do.
- Scanned PDFs need OCR: the image `apache/tika:3.3.1.0-full` has Tesseract, and the header `X-Tika-PDFOcrStrategy`
  (`auto`, `ocr_only`, `ocr_and_text_extraction`) turns it on. OCR is slow; the tests of this gem do not cover it.

### Other extractors

Any object with `types` (an Array of MIME types, or `nil` for any) and `extract(content, type:)` that returns
`{text:, title:, lang:}` is an extractor; `text` is a String or an Array of page Strings, and an optional `mark:` is
set on the record. It may have `open(context)` and `close`.

## Chunking

```ruby
flat_map Metacrunch::Ai::Chunk.new(size: 1000, overlap: 150)
map Metacrunch::Ai::Embed.new(embedder, text: ["title", "headings", "text"]), batch: 100
# {"id" => "handbook/loans.html#3", "parent_id" => "handbook/loans.html", "chunk" => 3,
#  "headings" => ["Loans", "Loan periods"], "pages" => [5, 6], "text" => "…", "title" => "Loans", …}
```

The step cuts a document's text into chunk records, as comparable tools do (LangChain's recursive splitter,
Unstructured's `by_title`):

1. Markdown headings start sections; each chunk knows the heading path it lies in.
2. A section is split at blank lines, then lines, sentence ends and spaces, and cut hard only where nothing else
   helps, until every piece fits `size`. Code blocks and tables stay whole while they fit.
3. The pieces are joined again into chunks of at most `size`; the next chunk of a section starts with whole pieces of
   the last one, up to `overlap`. Small consecutive sections share a chunk.

| Option | Default | |
|---|---|---|
| `text` | `"text"` | the field with the text: Markdown or plain text, or an Array of pages (numbered from 1) |
| `into` | `"text"` | the field of a chunk's text |
| `id` | `"id"` | the field with the document's id; a document without one fails |
| `size`, `overlap` | `1000`, `150` | the most a chunk holds, and how much of the last one the next repeats |
| `length` | characters | a callable that gives the length of a String, e.g. its tokens; `size` and `overlap` count in it |
| `headings` | `true` | `false` for plain text whose lines may start with `#` |
| `keep` | all | the document's fields to copy into its chunks; by default all but the text |

- A chunk's `id` is `"#{parent_id}##{n}"`, `chunk` its number from 1; `pages` (for page Arrays only) the pages its
  text comes from. Its text is at most `size` long, is not blank and does not begin with the headings of its path.
- `Embed` with `text: ["title", "headings", "text"]` puts the document's title and the heading path before the
  chunk's text, which helps a search find the right passage.
- A heading without text of its own and without subsections stays in the text as a line, under its parent's path,
  so that no heading is lost.
- A document without text gives no chunk and gets the mark "No text to chunk".
- `Chunk#split(text)` returns the chunks of a String or an Array of pages as `Chunk::Piece` (`text`, `headings`,
  `pages`), for use outside a step.

Embedding models count tokens, and refuse or cut texts above their limit. 1000 characters are about 250 tokens of
English text; to count exactly, pass the model's tokenizer, e.g. with the gem `tiktoken_ruby` for OpenAI's models:

```ruby
require "tiktoken_ruby"

encoding = Tiktoken.get_encoding("cl100k_base")
flat_map Metacrunch::Ai::Chunk.new(size: 400, overlap: 50, length: ->(text) { encoding.encode(text).size })
```

## From documents to a RAG index

A search over documents for retrieval-augmented generation (RAG) or semantic search needs passages, not whole
documents: a vector stands for a few hundred tokens, and a hit names the passage and its source. The usual way, which
[`examples/documents.rb`](examples/documents.rb) follows:

1. Read the documents: `Metacrunch::FileList::Reader` yields one record per file with its id, MIME type and SHA-256.
2. Extract the main content as Markdown, without navigation and footers, with page numbers for PDFs (`Extract`).
3. Chunk by structure, with a size well below the model's limit and some overlap (`Chunk`).
4. Embed each chunk with its title and heading path before the text (`Embed`).
5. Write the chunks with their document's id (`parent_id`), number, headings and pages, so an answer can cite them.

```
$ bundle exec metacrunch run examples/documents.rb --tika-url http://localhost:9997 \
    --embeddings-url http://localhost:11435/v1 --embeddings-model all-minilm \
    --output tmp/chunks.jsonl examples/data/documents
```

Each chunk is a record of its own (see [ADR 0007](../docs/decisions/0007-store-chunks-as-records-of-their-own.md)).
When documents change, the chunks of a changed or deleted document must go: build a new index from all documents and
switch an alias to it, as [metacrunch-elasticsearch](../metacrunch-elasticsearch#chunk-indices) shows for chunk
indices.

Catalog records and other short metadata need no chunking: build one text from their fields and embed it, one vector
per record.

```ruby
map Metacrunch::Ai::Embed.new(embedder, text: ->(record) {
  [record["title"], *record["creators"], *record["subjects"], record["abstract"]].compact.join("\n")
}), batch: 100
```

## Running the tests of this gem

The unit tests need no server. The integration tests run against the embeddings server at `EMBEDDINGS_URL` with the
model `EMBEDDINGS_MODEL` (`all-minilm` by default) and against the Tika server at `TIKA_URL`, and those that need a
server are skipped without its variable; [`test/compose.yml`](test/compose.yml) starts Ollama and Tika with Docker:

```
$ docker compose -f test/compose.yml up -d --wait
$ docker compose -f test/compose.yml exec ollama ollama pull all-minilm
$ EMBEDDINGS_URL=http://localhost:11435/v1 TIKA_URL=http://localhost:9997 bundle exec rake
$ docker compose -f test/compose.yml down
```

## License

MIT, see [License.txt](License.txt).
