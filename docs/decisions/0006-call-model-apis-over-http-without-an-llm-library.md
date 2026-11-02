# 6. Call model APIs over HTTP without an LLM library

- Status: accepted
- Date: 2026-11-02

## Context

metacrunch-ai embeds texts, and later steps are to classify, decide, extract and generate with language models. The
services are many: OpenAI, Azure OpenAI, Voyage AI, Cohere, Mistral, Google, AWS, and servers on one's own machine
such as Hugging Face Text Embeddings Inference, Ollama and vLLM. Most of them offer the OpenAI embeddings API
(`POST /embeddings`, texts in, vectors by index out), some with a field or header of their own.

Ruby has libraries that hide the differences. ruby_llm is the healthiest of them in 2026: many providers, chat,
embeddings, structured output and batch APIs, Ruby 4.0 in its CI. It brings faraday, faraday-retry,
faraday-multipart, marcel, zeitwerk and schematist, is configured globally (`RubyLLM.configure`), retries on its own,
and published about twenty releases in a year. langchainrb has had no release for a year and a half; the official
SDKs of OpenAI and Anthropic each cover one provider.

What a metacrunch step needs from a service is narrow: one request with many texts, an answer per text, and errors
that say whether a text, the request or the service is at fault, so the failure policy can act per record.
Retries, rate limits, batching and the log of costs belong to the step, the same in every worker process.

## Decision

metacrunch-ai talks to services itself, over Ruby's `net/http`: `Metacrunch::Ai::Http` (one persistent connection
per process, JSON, retries with a growing delay and `Retry-After`, errors by status) and adapters on top of it, first
`Metacrunch::Ai::OpenAi` for the OpenAI embeddings API, with further headers and request fields for the services
that differ in little. The steps take any object with `embed(texts)` as embedder, so a library can be plugged in with
a few lines; the Readme shows one for ruby_llm. The gem depends on nothing but metacrunch.

## Alternatives

- ruby_llm as the base: the most providers at once, but six dependencies, a global configuration where metacrunch
  binds params per job, a retry policy beside the step's, a fast-moving API, and errors that would have to be mapped
  back to records.
- The official SDKs: a dependency per provider, and still a layer of our own above them.
- langchainrb: unmaintained.

## Consequences

- Adapters are ours to maintain. One request shape covers most services; another (Cohere's, Google's) is an adapter
  of a few dozen lines.
- The behaviour on errors is the same for every service and fits the failure policy: refused input fails single
  records, an unavailable service the records of a request, a wrong key or model stops the job when it opens.
- Later LLM steps reuse `Http`.
- Users who need a provider the gem lacks write a small embedder or wrap a library of their choice.
