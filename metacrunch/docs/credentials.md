# Credentials

Secrets, such as API keys and passwords, live in encrypted files in the project. A `secret` parameter refers to them
in its default or in a [params file](jobs.md#parameter-files):

```ruby
params do
  secret :api_key, String, default: {credential: "catalog.api_key"}
end
```

```
$ metacrunch credentials edit                    # opens $VISUAL or $EDITOR
$ metacrunch credentials edit -e production
$ metacrunch credentials show -e production
$ metacrunch credentials rotate -e production
```

`edit` creates `.metacrunch/credentials.yml.enc`, which you commit, and the key `.metacrunch/master.key`, which you
never commit (`.metacrunch/.gitignore` excludes it). The file holds YAML: `{credential: "catalog.api_key"}` reads
`api_key` below `catalog`. Every value is read as its text and converted like a command-line value, so `0123`, `no`
or `on` need no quotes; an empty value, `~` and `null` mean "not set". `edit` refuses to save invalid YAML and, on a
terminal, offers to edit again.

Each [environment](environments.md) has its own credentials file and key:

| Environment | File | Key |
|---|---|---|
| `default` (no `-e`, no `METACRUNCH_ENV`) | `.metacrunch/credentials.yml.enc` | `.metacrunch/master.key` |
| `-e production` | `.metacrunch/credentials.production.yml.enc` | `.metacrunch/master.production.key` |

A run in `production` reads only the production file, never the one of the default environment, so laptops and CI need
not hold the production key. [`examples/credentials`](../examples/credentials) has a runnable example.

- **Where:** `--credentials DIR` or `METACRUNCH_CREDENTIALS`, else the nearest `.metacrunch/` above the job file
  (for a job or command run by name: above the project's `Metacrunchfile`), else `~/.metacrunch/` for personal
  credentials. The directory found decides alone; `-v` logs the file that was decrypted. `metacrunch credentials`
  looks above the working directory and uses `~/.metacrunch/` only with `--credentials ~/.metacrunch`.
- **Key:** `METACRUNCH_MASTER_KEY`, else the key file of the environment. The variable is the key of whatever
  environment a run selects; a machine that runs several environments keeps one key file per environment instead. In
  containers and CI, set `METACRUNCH_MASTER_KEY`; with Kamal, list it under `env: secret:` and provide it in
  `.kamal/secrets`.
- **When:** credentials are decrypted only when a `{credential: ...}` reference needs its value: a value on the
  command line or in the params file wins without reading them, and a container whose params file takes every secret
  from `{env: ...}` needs neither key nor file (see [Environments](environments.md#examples)).
- **Missing values:** a reference that finds nothing fails and names the file:
  `api_key: credential catalog.api_key from default: not in /srv/catalog/.metacrunch/credentials.production.yml.enc`.
- **Secrets:** only a `secret` may refer to the credentials. It is hidden in `--help`, messages and `params.inspect`,
  and a plain value on the command line, where `ps` and the shell history show it, gives a warning (see
  [Secrets](jobs.md#secrets)). What a job does with the value, such as logging it or putting it into an exception, is
  not hidden. `Metacrunch::Testing` never reads credentials: a reference fails with `api_key: Testing reads no
  credentials; pass api_key in params:`.
- **Rotation:** `rotate` encrypts a file with a new key and replaces the key file, or prints the new key if the old
  one came from `METACRUNCH_MASTER_KEY`. If a `master[.ENV].key.new` is left behind (rotate died between its two
  renames), check first: if `metacrunch credentials show` fails with "wrong key", the `.new` file holds the key of the
  new file, so rename it to `master[.ENV].key`; otherwise delete it. `rotate` refuses to run while it exists.

Keep in mind:

- While the editor runs, `edit` keeps the plaintext in a temporary file (mode 0600 in a directory with mode 0700) and
  removes it afterwards; only SIGKILL leaves it behind. Ctrl-C meanwhile reaches only the editor.
- Editors may keep copies of the plaintext: vim's swap and backup files, VS Code's Local History. Turn them off for
  these files if that matters to you (in vim, for example, `EDITOR="vim -n -c 'set nobackup nowritebackup'"`).
- `.metacrunch/.gitignore` keeps the keys in `.metacrunch/` out of git. A key in a directory given with
  `--credentials` needs an ignore rule of its own.
- The plaintext stays in the memory of every process that uses it, workers included.
- Other processes of the same user can read `METACRUNCH_MASTER_KEY` from a process's environment
  (`/proc/PID/environ` on Linux).
- A lost key cannot be recovered: delete the file and create it again with `edit`.
