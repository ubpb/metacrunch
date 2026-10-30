# 3. Input unpacks what a source asks for, and archives on one level

- Status: accepted
- Date: 2026-10-30

## Context

`Metacrunch::Input` gives sources their documents. It detected gzip, tar and zip by their content and unpacked them,
and it detected the content again: a tar in a tar, a zip in a zip and an archive in a `.tar.gz` were unpacked too, up
to four layers. A source reads every document in its format and does not check whether the document suits it. A CSV
reader reads a `readme.txt` as CSV, whether it comes from an archive or is given directly.

The recursion showed its cost with zip support. Excel, Word, OpenDocument and EPUB files are zip archives. An `.xlsx`
in a zip of CSV files was taken apart into its XML parts, and a reader of workbooks could never get one from inside
an archive. A first answer refused Office files by their content. That was a special case with a list without an
end (jar, nupkg and 3mf are zip-based too), and it judged the content, which Input does nowhere else.

## Decision

- **Input unpacks only what it is asked to.** `Input.new(targets, unpack: [...])` takes `:gzip`, `:tar` and `:zip`.
  Without `unpack:` nothing is unpacked, and a format that is not named comes as a document with its bytes.
- **The readers pass `unpack:` on, with gzip as their default.** These are `JsonLines::Reader`, `Csv::Reader` and
  `Marc::Reader`; the generator's source template names gzip itself. A job that reads tar or zip archives names them,
  and `metacrunch run -i` takes `--unpack`. A reader of a ZIP-based format leaves `:zip` out.
- **Readers of text refuse what they do not unpack.** With `packed: :refuse`, a gzip, tar or zip document that
  `unpack:` leaves out raises an error that names the `unpack:` to pass. Read as text, its bytes would give wrong
  records, for CSV without any error.
- **gzip is decompressed wherever it is.** It compresses one file and brings in nothing else: `.tar.gz` and `.zip.gz`
  files are read as `.tar` and `.zip` files are, and a `.jsonl.gz` file in an archive is decompressed.
- **Archives are unpacked on one level, as `tar -x` and `unzip` do.** A tar or zip in an archive is a document; a
  gzip-compressed one gives its content.
- **Formats are detected by their content.** What metacrunch cannot read (bzip2, xz, zstd, split zip) stays an error.
- **Whether the input suits a job is the responsibility of whoever provides it**, and the documentation says so.

## Alternatives

- **Recursive unpacking with a check of the content** (refuse Office, EPUB and OpenDocument files): a special case
  that grows with every ZIP-based format and still lets a `readme.txt` through. It was withdrawn.
- **One layer in total:** breaks `.tar.gz`, the most common delivery.
- **Each format at most once:** an `.xlsx` in a `.tar.gz` would still be unpacked, since zip is not used up.
- **Deciding by the file name** (only `.zip` is zip): stdin and IOs have no name, downloads often have odd ones, and
  gzip and tar are detected by their content.
- **Everything unpacked by default, with a switch to turn it off:** Input would decide for sources that do not know
  it. Asking for each format is explicit.
- **Readers that unpack all three by default:** a job would read the files of an archive without ever saying so, and
  archives are where unexpected files come from.
- **Readers without a default, or with `unpack:` required:** explicit, but every job, also one that reads a `.gz`
  file, would have to name gzip, which brings in nothing but the file it compresses.

## Consequences

- Jobs read `.gz` files as before. A job that reads tar or zip archives says so with `unpack:`, or `--unpack` for `-i`;
  without it, a reader stops at the archive and names the `unpack:` to pass.
- A tar of tars or a zip in a `.tar.gz` is no longer unpacked; such deliveries are unpacked first. Nested unpacking
  on request can be added later, as a depth for `unpack:`.
- A later reader of workbooks gets them as documents, given directly or from inside an archive.
- A source built directly on Input must name what it unpacks, as the generator's template shows.
- Choosing documents by name (`only: "*.csv"`) stays open, should mixed deliveries become a problem in practice.
