# metacrunch-ng, sub-project 6: encrypted credentials

- Date: 2026-10-11
- Branch: `metacrunch-ng`
- Status: approved design; not implemented
- Builds on: [sub-project 1 spec](2026-10-10-metacrunch-ng-core-design.md)
  (parameters, 5.5), [sub-project 2 spec](2026-10-10-metacrunch-ng-cli-pipes-design.md)
  (CLI commands)

## 1. Context

Jobs declare parameters (`params { param ... }`). Values come from the
command line, then an environment variable (`env:`), then the default. Some
parameters are secrets: API keys, database and Elasticsearch passwords.
Today they must be typed on the command line, where `ps` and the shell
history show them, or exported as environment variables by hand.

Rails keeps the secrets of a project encrypted in the project
(`config/credentials.yml.enc`) and the key outside version control
(`config/master.key` or `RAILS_MASTER_KEY`). Kamal adds environment
variables on top. This sub-project brings the same model to metacrunch.

Jobs run from repository checkouts (laptops, servers, cron) and in Docker
containers and CI. A key must therefore come from a file or from an
environment variable, and the credentials must be found regardless of the
working directory.

Sub-projects 3 (declarative jobs) and 4 (Fix language) were dropped on
2026-10-11; the numbers stay as names, so this is sub-project 6.

### 1.1 Goals

1. A secret is entered once with `metacrunch credentials edit` and committed
   encrypted. A job that declares it gets the value without a command-line
   argument or environment variable, from any working directory.
2. Each environment (development, production, ...) has its own file and its
   own key, so production secrets never need to be on laptops or in CI.
3. The same project runs from a checkout (key file) and in a container
   (`METACRUNCH_MASTER_KEY`), and environment variables override single
   values, as in Kamal.
4. Secret values never appear in help texts, error messages, logs or
   `params.inspect`.

### 1.2 Non-goals

- Compatibility with the Rails file format or naming.
- Encrypting single values so that diffs show keys and conflicts can be
  merged (as sops does). Every environment is one opaque file.
- A git diff driver (`rails credentials:diff`).
- Access to credentials other than through parameters (no `credentials.*`
  in jobs).
- `secret: true` for parameters without `credential:`, `cli: false` to
  forbid the command line for a parameter, `--global` as a shortcut for
  `--credentials ~/.metacrunch`.
- A file of plain (unencrypted) parameter values per environment.
- Wiping plaintext from memory.

### 1.3 Success criteria

1. In a temporary project, `credentials edit` with a scripted editor creates
   `.metacrunch/credentials.yml.enc`, `.metacrunch/master.key` (mode 0600)
   and `.metacrunch/.gitignore`. `metacrunch run` of a job with a
   `credential:` parameter, started from another directory, gets the value.
2. `-e production` (or `METACRUNCH_ENV=production`) uses
   `credentials.production.yml.enc` with `master.production.key` or
   `METACRUNCH_MASTER_KEY`. Without that file nothing falls back to
   `credentials.yml.enc`, and a required parameter names the missing file.
3. A job whose credential parameters all come from environment variables
   runs without key and credentials file.
4. The secret string appears nowhere in the output of `--help`, of failed
   runs (invalid value, missing key, wrong key), of `-v` logs, or of
   `params.inspect` and `pp params`.
5. After `credentials rotate` the old key cannot decrypt the file. A
   rotation that fails before it renames anything leaves old key and file
   usable.
6. The engine keeps its cost (about 62 ns per step and record). `bundle
   exec rake` passes (coverage at least 95 % lines and 90 % branches,
   RuboCop).

### 1.4 Decisions

| Question | Decision |
|---|---|
| Approach | Own file format on the standard library: OpenSSL AES-256-GCM, YAML inside. No new dependency. |
| Where the files are | `.metacrunch/` in the project, found upward from the job file; `~/.metacrunch/` if there is none; `--credentials DIR` / `METACRUNCH_CREDENTIALS` override both |
| Environments | One file and one key per environment: `credentials[.ENV].yml.enc`, `master[.ENV].key`. Selected with `-e, --environment` or `METACRUNCH_ENV`. No fallback to the file without environment. |
| Key from the environment | `METACRUNCH_MASTER_KEY` before the key file |
| How jobs get secrets | Only through parameters: `credential: "fis.api_key"`. Order: command line, `env:`, credentials, default. |
| Loading | Lazy: only when a credential parameter gets no value from the command line or `env:` |
| Redaction | A parameter with `credential:` is secret: hidden in `--help`, error messages, `inspect` and `pp` |
| Secret on the command line | Allowed, with a warning |
| Commands | `metacrunch credentials edit`, `show`, `rotate` |

## 2. Files, keys and environments

### 2.1 Layout

```
project/
├── .metacrunch/
│   ├── .gitignore                       # master*.key, created by edit
│   ├── credentials.yml.enc              # no environment
│   ├── credentials.production.yml.enc
│   ├── master.key                       # not committed
│   └── master.production.key            # not committed, only where production runs
└── jobs/
    └── ris2fis.rb
```

`~/.metacrunch/` has the same layout and holds personal credentials, e.g. an
API token used in several projects or by jobs outside a project.

### 2.2 Finding the credentials directory

For `run`, `check`, `trace` and `Job#run`, the first that applies:

1. `--credentials DIR`, then the environment variable
   `METACRUNCH_CREDENTIALS`. DIR is the directory that holds the files.
2. The nearest `.metacrunch/` directory, looking upward from the directory
   of the job file, starting with that directory itself. The job file's
   symlinks are resolved first (`File.realpath`), so
   `/usr/local/bin/x → project/jobs/x.rb` belongs to `project`. A job
   without a file (defined in Ruby code, not loaded by `Metacrunch.load_job`)
   skips this step.
3. `~/.metacrunch/` (`HOME` taken from the environment), if it is a
   directory.

The directory found decides alone. A project `.metacrunch/` that lacks the
file of the selected environment gives no credentials; the search does not
continue upward or to `~/.metacrunch/`. Credentials are never merged from
several directories. For a project below the home directory, step 2 reaches
`~/.metacrunch/` by itself; step 3 covers projects elsewhere (`/opt/jobs`).

With `-v` the run logs which file it decrypted (`credentials: PATH`), so a
project that silently uses personal credentials from `~/.metacrunch/` is
visible. Every error message names the file.

### 2.3 Environments

- Selected by `-e, --environment NAME`, else `METACRUNCH_ENV`. An empty
  variable counts as unset.
- Names match `\A[a-z0-9_-]+\z`. A wrong name is a usage error as soon as
  the command starts, whether or not a credential is needed.
- Without an environment the files are `credentials.yml.enc` and
  `master.key`; with `production` they are `credentials.production.yml.enc`
  and `master.production.key`.
- No fallback: with an environment selected, only that environment's file
  counts. A forgotten production file must not make production use the
  development secrets.

### 2.4 Keys

The key for the selected file is, in this order:

1. `METACRUNCH_MASTER_KEY` (empty counts as unset). A server or container
   runs one environment, so one variable suffices.
2. `master[.ENV].key` in the credentials directory.

A key is needed only to decrypt (2.5) or write (5) a file.

### 2.5 Lazy loading

The credentials directory is searched, the key read and the file
decrypted only when a parameter with `credential:` gets no value from the
command line or its `env:` variable. A file is decrypted at most once per
bind. `--help` never touches credentials, because it binds no values.
`check` binds the parameters and so also checks that key and file fit.

## 3. Format and cryptography

### 3.1 Key

32 random bytes (`SecureRandom.random_bytes`), written as 64 lowercase hex
characters and a newline. Whitespace around the key is ignored when it is
read (from a file or `METACRUNCH_MASTER_KEY`). Anything else than 64 hex
characters is an error: `invalid key from METACRUNCH_MASTER_KEY: expected
64 hex characters`.

### 3.2 Encryption

AES-256-GCM (`OpenSSL::Cipher.new("aes-256-gcm")`). Every write uses a new
random 12-byte IV. The 16-byte authentication tag detects a wrong key and
any change to the file. The header line (3.3) is authenticated additional
data, so it cannot be swapped unnoticed. With random 96-bit IVs one key is
safe for far more writes than a credentials file will ever see.

### 3.3 File format

Two lines of text:

```
metacrunch credentials v1
<strict Base64 of iv (12 bytes) + tag (16 bytes) + ciphertext>
```

The version allows another scheme later. Text keeps git treating the file
as text; its content stays opaque.

### 3.4 Plaintext

UTF-8 YAML, read with `YAML.safe_load(text, aliases: true)`: only plain
types (String, Integer, Float, true, false, nil, Array, Hash). Anchors and
aliases may share values inside one file. Other types (a date written as
`2026-10-11`) are an error that names the type and suggests quoting. The top
level must be a Hash; an empty file or one with only comments counts as
`{}`.

```yaml
fis:
  api_key: sk-123
es:
  password: geheim
  hosts: [es1, es2]
```

A credential path such as `fis.api_key` splits at dots and follows String
keys through nested Hashes. A missing key, a `nil` value or a non-Hash on
the way means "not in the file". Keys that contain a dot cannot be
addressed.

### 3.5 Writing

Files are written atomically: to a temporary file in the same directory,
then `File.rename`. Credentials files get mode 0644 (they are committed),
key files 0600 from the moment they are created.

### 3.6 Errors

`Metacrunch::CredentialsError < ParamError`. Messages name the file and the
source of the key, never a value:

| Case | Message |
|---|---|
| Header missing or not Base64, too short | `not a metacrunch credentials file: PATH` |
| Other version | `unsupported credentials format in PATH: v2` |
| Authentication fails | `cannot decrypt PATH: wrong key or modified file (key from METACRUNCH_MASTER_KEY)` |
| No key | `no key for PATH: set METACRUNCH_MASTER_KEY or create .../master.production.key` |
| YAML syntax | `invalid YAML in PATH at line 3, column 5`: only line and column, because Psych messages can quote content |
| Not a Hash, unsupported type | `PATH must contain a mapping at the top level`, `unsupported value in PATH: Date (quote it)` |
| Directory given but missing | `credentials directory not found: DIR` |

## 4. Parameters

### 4.1 Declaration

```ruby
params do
  param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key", required: true, desc: "FIS API key"
  param :es_password, String, credential: "es.password"
end
```

- `credential:` is a path of non-empty segments separated by dots
  (`\A[^.]+(\.[^.]+)*\z`), checked when the parameter is declared.
- It combines with `env:`, `required:` and `default:` (the default is the
  last fallback). Without `env:`, only the command line (with a warning,
  4.4) and the credentials provide the value. This is the way to make sure
  that an inherited environment variable cannot override a secret.

### 4.2 Resolution

For each parameter, the first that gives a value:

1. the command line;
2. the `env:` variable (empty counts as unset);
3. the credentials, at the `credential:` path (lazy, 2.5);
4. the default.

A required parameter without value is an error (4.5). Values from the
credentials are converted and checked like values from the command line:
`"42"` and `42` both give an Integer, a YAML list gives an Array, `true`
and `"yes"` give true. A Hash is never a valid value.

`Params#bind_argv(argv, env:, credentials:, warn:)` gets the credentials as
a lazy store object (6) and a callable for warnings. `bind_hash` (used by
`Testing.run`) ignores `credential:`; tests pass values directly:
`Testing.run(job, params: {api_key: "x"})`.

### 4.3 Secrets

A parameter with `credential:` is secret.

- `--help` shows its sources but no value and no default:
  `--api-key VALUE   FIS API key (required, secret, env: FIS_API_KEY, credential: fis.api_key)`
- Errors print `(hidden)` instead of the value:
  `invalid value for --api-key from credential fis.api_key in PATH: (hidden) is not an Integer`.
  The same holds for values from the command line and `env:`.
- `params.inspect`, `params.to_s` and `pp params` show `api_key=[secret]`.
  `params.api_key` and `params.to_h` return the real value.
- An invalid default of a secret parameter is reported without the value.

What a job does with the value (log it, put it into an exception message)
is not redacted.

### 4.4 Secrets on the command line

Allowed, for quick tries on a laptop. The run warns on stderr:

```
--api-key is a secret; pass it by FIS_API_KEY or credentials instead
```

Without `env:` the warning only names the credentials.

### 4.5 Missing required values

The message lists every source that was tried:

```
missing required parameter --api-key (FIS_API_KEY unset; fis.api_key not in /p/.metacrunch/credentials.production.yml.enc)
missing required parameter --api-key (FIS_API_KEY unset; no credentials for environment production in /p/.metacrunch)
missing required parameter --api-key (no credentials directory: no .metacrunch/ above /p/jobs/x.rb, no ~/.metacrunch/)
```

### 4.6 Library API

- `Job#file` is the expanded path of the file the job was loaded from
  (`Metacrunch.load_job`), else `nil`.
- `Job#run(argv, env:)` builds the store from `env`: `METACRUNCH_ENV`,
  `METACRUNCH_CREDENTIALS`, `METACRUNCH_MASTER_KEY`, `HOME` and the job's
  file. It passes the logger's `warn` as the warning callable.
- `Testing.run` is unchanged and never reads credentials.
- With workers, the parent binds the parameters before it forks; workers
  inherit the values. The store is never used in a worker.

## 5. The `credentials` command

```
metacrunch credentials edit   [-e ENV] [--credentials DIR]
metacrunch credentials show   [-e ENV] [--credentials DIR]
metacrunch credentials rotate [-e ENV] [--credentials DIR]
```

The environment comes from `-e` or `METACRUNCH_ENV`, the key as in 2.4. The
options may stand before or after the subcommand; an unknown or missing
subcommand is a usage error (exit status 2).

### 5.1 Directory

There is no job file, so the command starts from the working directory:

1. `--credentials DIR`, then `METACRUNCH_CREDENTIALS`.
2. The nearest `.metacrunch/` upward from the working directory, **except
   `~/.metacrunch/`**. Otherwise `edit` in a new project below the home
   directory would silently open the personal credentials.
3. Nothing found: `edit` creates `./.metacrunch/`; `show` and `rotate` fail
   with `no .metacrunch/ found above DIR; use --credentials`.

The personal credentials are edited with `--credentials ~/.metacrunch`.
Every subcommand first names its file on stderr, e.g.
`Editing .metacrunch/credentials.production.yml.enc`.

### 5.2 `edit`

1. **Existing file:** decrypted with the key of 2.4.
2. **New file:**
   - The key is `METACRUNCH_MASTER_KEY` or an existing key file. If there
     is neither, a new key is written to `master[.ENV].key` (0600), and
     stderr says `Created .metacrunch/master.production.key: keep it safe;
     it is not committed`.
   - `.metacrunch/.gitignore` with the line `master*.key` is created if it
     does not exist. The project's own `.gitignore` is not touched.
   - The plaintext starts as a commented YAML template that shows the path
     syntax.
3. **Editor:** `VISUAL`, else `EDITOR`, split with `Shellwords` (so
   `code --wait` works); neither set is an error (`set VISUAL or EDITOR`).
   The plaintext is written to `credentials[.ENV].yml` (mode 0600, the
   `.yml` suffix gives syntax highlighting) in a new temporary directory
   (mode 0700). The editor runs in the foreground with the terminal.
4. **After the editor:**
   - Non-zero exit status: nothing is saved (exit 1).
   - Content unchanged and the file existed: nothing is written
     (`No changes`).
   - Invalid YAML or a top level that is not a Hash: the error (3.6) is
     shown. On a terminal the command asks `Edit again? [Y/n]` and reopens
     the editor with the same content; otherwise, or on "n", nothing is
     saved (exit 1).
   - Otherwise the content is encrypted with a new IV and written
     atomically. A new file is saved even if the template was not changed.
5. The temporary directory is removed in every case, also on errors and
   Ctrl-C. Only SIGKILL can leave it behind (documented).

### 5.3 `show`

Decrypts the file and writes the plaintext to stdout. A missing file is an
error.

### 5.4 `rotate`

1. Decrypt with the current key. A missing key or file, or a failure, ends
   the command; nothing is changed.
2. Generate a new key and encrypt the plaintext with it (new IV) into a
   temporary file next to the credentials file.
3. If the current key came from the key file: write the new key to
   `master[.ENV].key.new` (0600), rename the temporary credentials file to
   its name, then rename the `.new` key over the key file. If the command
   dies between the two renames, `master[.ENV].key.new` holds the key of the
   new file; the Readme says to rename it.
4. If the current key came from `METACRUNCH_MASTER_KEY`: no key file is
   written. The new key is printed once on stdout (only the key, so it can
   be captured), and stderr says `update METACRUNCH_MASTER_KEY wherever it
   is set`. If a key file exists as well, stderr warns that it still holds
   the old key.
5. Any error before the first rename removes the temporary files and leaves
   key and file as they were.

### 5.5 Options of `run`, `check` and `trace`

```
-e, --environment NAME   Credentials environment (default: METACRUNCH_ENV)
    --credentials DIR    Credentials directory (default: METACRUNCH_CREDENTIALS,
                         then .metacrunch/ above the job file, then ~/.metacrunch/)
```

They belong to `JobCommand`, so all three commands get them. `-e` is not yet
used by any command.

## 6. Architecture

| Unit | Responsibility |
|---|---|
| `Credentials::Key` (new) | Generates keys, parses hex keys, knows where a key came from (for messages) |
| `Credentials::Box` (new) | Format v1: encrypts plaintext to file content, decrypts and authenticates it |
| `Credentials::Location` (new) | Finds the directory (2.2, 5.1), names the files of an environment, finds the key (2.4), validates environment names |
| `Credentials::Store` (new) | Lazy: on the first `dig(path)` it locates, decrypts and parses once; `dig` returns the value or nil; `missing(path)` explains why a value is absent (4.5); logs the decrypted file at debug level |
| `Credentials::Editor` (new) | Temporary directory, editor process, YAML check, "edit again" loop |
| `Cli::CredentialsCommand` (new) | `edit`, `show`, `rotate` |
| `Params` | `credential:`, secret redaction, resolution with store and warning callable, messages for missing values |
| `Cli::JobCommand` | `-e`, `--credentials`; builds the store; passes `logger.warn` |
| `Job`, `Loader` | `Job#file`; `Job#run` builds the store from `env` |
| `errors.rb` | `CredentialsError < ParamError` |

Layout:

```
lib/metacrunch/credentials.rb            requires the parts below
lib/metacrunch/credentials/key.rb
lib/metacrunch/credentials/box.rb
lib/metacrunch/credentials/location.rb
lib/metacrunch/credentials/store.rb
lib/metacrunch/credentials/editor.rb
lib/metacrunch/cli/credentials.rb
```

New requires, all from the standard library or default gems: `openssl`,
`securerandom`, `yaml`, `tmpdir`, `shellwords`. Strict Base64 uses
`pack("m0")` and `unpack1("m0")`, because `base64` is a bundled gem since
Ruby 3.4 and would need a gemspec dependency. The engine, the executors and
the step chain do not change.

## 7. Exit codes

| Situation | Exit status |
|---|---|
| `CredentialsError` (key, file, YAML, environment name, directory) in any command | 2, as other parameter errors |
| `credentials edit`: editor failed, invalid YAML not fixed | 1 (nothing saved) |
| Ctrl-C during `edit` | 130, temporary directory removed |

## 8. Security notes

These go into the Readme:

- The plaintext exists in a temporary file (0600 in a 0700 directory) while
  the editor is open, and in the memory of every process that uses the
  credentials, workers included.
- A key in `METACRUNCH_MASTER_KEY` is visible to processes of the same user
  that can read the environment of another process (`/proc/PID/environ` on
  Linux), as with `RAILS_MASTER_KEY`.
- Values typed on the command line are visible in `ps` and in the shell
  history; hence the warning (4.4).
- `.metacrunch/.gitignore` protects key files in `.metacrunch/` only.
- Losing a key makes its file unreadable. There is no recovery; delete the
  file and create it again with `edit`.

## 9. Tests

### 9.1 Unit tests

- `Key`: generate (64 hex), parse with whitespace, reject wrong length and
  non-hex characters; messages name the source, never the key.
- `Box`: round trip; a flipped byte in IV, tag, ciphertext or header, a
  wrong key, a foreign header, a newer version and garbage each raise the
  error of 3.6; two writes of the same plaintext differ (new IV).
- `Location`: explicit directory before the variable; upward search from a
  nested job file; symlinked job file; nearest `.metacrunch/` wins; a
  project without the environment's file does not fall back; `HOME`
  fallback (HOME injected); a job without file; the command's rule that
  skips `~/.metacrunch/`; environment name validation; key from the
  variable before the file.
- `Store`: lazy (no file is opened when every credential parameter gets its
  value from the command line or `env:`; checked against a directory whose
  credentials file is unreadable); decrypts once; `dig` through nested
  Hashes, missing keys, `nil`, non-Hash on the way; `missing` texts; YAML
  errors give line and column only; disallowed types; debug log line.
- `Params`: resolution order; conversion of YAML types; required with every
  missing variant; `credential:` validation; redaction in `help`, in
  invalid-value errors (command line, env, credentials, default), in
  `inspect` and `pp`; the warning for a secret on the command line and its
  absence for other parameters; `bind_hash` ignores credentials.

Redaction tests assert that the real secret string does not occur in the
output.

### 9.2 Command tests

- `edit` with a scripted editor (a Ruby script given as `EDITOR` that writes
  a fixed content): creates key (0600), file and `.gitignore`; edits an
  existing file; editor failure saves nothing; unchanged content writes
  nothing; invalid YAML without terminal saves nothing; the temporary
  directory is gone afterwards in every case; `VISUAL` before `EDITOR`;
  neither set.
- `show`; `rotate` with a key file and with `METACRUNCH_MASTER_KEY` (new key
  on stdout, warning about a stale key file); after rotation the old key
  fails; a failure before the renames (simulated) changes nothing.
- Directory rules of 5.1, including that `edit` below `HOME` does not pick
  `~/.metacrunch/`.

### 9.3 End to end

Through `exe/metacrunch` in a temporary project, started from another
working directory:

- `run` and `check` with a credential parameter, with `-e production`, with
  `METACRUNCH_MASTER_KEY` and without key file, with the `env:` variable
  overriding the credential, and with all values from `env:` and no
  `.metacrunch/` at all.
- A wrong key ends with exit status 2 and a message that names the file.
- `run -w 2` gets the secret into the workers.
- The secret string does not occur in stdout or stderr of any of these runs,
  with `-v` included.

## 10. Documentation

- Readme, new section "Credentials": the `edit` workflow, the directory and
  key rules, environments, the resolution order of parameters, containers
  and CI with `METACRUNCH_MASTER_KEY`, Kamal (`env: secret:` with the key),
  `rotate` and its recovery note, what is redacted and what is not, the
  security notes of 8.
- Readme, "Parameters": `credential:` in the example and the order of
  sources; the options of 5.5 in the `run` table.
- CHANGELOG: encrypted credentials, the `credentials` command, `-e` and
  `--credentials`.

## 11. Deferred

- `secret: true` for parameters that only come from `env:`.
- `cli: false` to refuse a parameter on the command line.
- `--global` for `--credentials ~/.metacrunch`.
- A git diff driver for credentials files.
- A plain parameter file per environment (`.metacrunch/params.production.yml`),
  which would fit into the same directory.
