# metacrunch-ai

AI steps for [metacrunch](https://github.com/ubpb/metacrunch), starting with embeddings: a step that adds a vector
to each record, through the OpenAI embeddings API and the many servers that offer it, hosted or on your own machine.
The vectors go wherever metacrunch writes, for example into an Elasticsearch index for semantic or hybrid search.

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
Lines into JSON Lines.

## Installation

metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch-ai"
end
```

The gem needs nothing but metacrunch: it talks to the services with Ruby's `net/http`.

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
- The service is overloaded or away (429, 500, 502, 503, 504, timeouts, lost connections): the request goes again after
  1, 2, 4, … up to 60 seconds, or after the time `Retry-After` names. If it still fails after `retries`, the records of
  the request fail with `Metacrunch::Ai::Unavailable`.
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

## Running the tests of this gem

The unit tests need no server. The integration tests run against the embeddings server at `EMBEDDINGS_URL` with the
model `EMBEDDINGS_MODEL` (`all-minilm` by default) and are skipped otherwise; [`test/compose.yml`](test/compose.yml)
starts Ollama with Docker:

```
$ docker compose -f test/compose.yml up -d --wait
$ docker compose -f test/compose.yml exec ollama ollama pull all-minilm
$ EMBEDDINGS_URL=http://localhost:11435/v1 bundle exec rake
$ docker compose -f test/compose.yml down
```

## License

MIT, see [License.txt](License.txt).
