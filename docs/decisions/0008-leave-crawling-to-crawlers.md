# 8. Leave crawling to crawlers

- Status: accepted
- Date: 2026-11-03

## Context

metacrunch-ai turns documents into chunks with vectors for search and retrieval-augmented generation. Many of those
documents are on the web: the pages of a website, full texts that catalog records link, documents an API lists.

Getting the pages of a site is crawling: following links without getting lost, honouring robots.txt and sitemaps,
keeping each server's load low, rendering pages that need JavaScript, telling duplicates apart, resuming a crawl,
fetching only what changed. Specialized tools have done this for years: wget and HTTrack for mirrors, Scrapy and
Crawlee as frameworks, Heritrix and Browsertrix for archives (writing WARC), Crawl4AI and Firecrawl with Markdown
output. Ruby has no maintained building blocks for it; its robots.txt and sitemap gems are unmaintained.

## Decision

metacrunch does not crawl. It starts at what crawlers leave, and adds small parts for documents whose URLs are known
without crawling:

- `Metacrunch::FileList::Reader` reads a crawler's files, Markdown with front matter included.
- `Metacrunch::Ai::Sitemap::Reader` reads the pages a website lists in its sitemaps.
- `Metacrunch::Ai::Fetch` downloads the URL a record holds, politely: a user agent, a delay per host, robots.txt
  (RFC 9309), a bounded number of redirects. It follows no links.

The Readme of metacrunch-ai shows how a crawler's output goes into a job.

## Alternatives

- An own crawler: following links, a crawl frontier (Redis would do), politeness per host, change detection. It
  would take long to build well, still lack JavaScript rendering, and stay behind the tools above.
- Binding a crawler library or service: none is in Ruby, and calling one is no better than reading its files.

## Consequences

- Following links, JavaScript rendering, crawl frontiers and resuming crawls stay outside metacrunch.
- A site with a sitemap and records with URLs need no crawler at all.
- A mirror on disk loses the original URLs and HTTP headers; a source for WARC files, which keep them, may follow.
