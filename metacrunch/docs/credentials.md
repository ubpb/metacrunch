# Credentials

Parameters can read secrets, such as API keys and passwords, from encrypted files in the project:

```ruby
params do
  param :api_key, String, env: "CATALOG_API_KEY", credential: "catalog.api_key", required: true
end
```

```
$ metacrunch credentials edit                    # opens $VISUAL or $EDITOR
$ metacrunch credentials edit -e production
$ metacrunch credentials show -e production
$ metacrunch credentials rotate -e production
```

`edit` creates `.metacrunch/credentials.yml.enc`, which you commit, and the key `.metacrunch/master.key`, which you
never commit (`.metacrunch/.gitignore` excludes it). The file holds YAML: `credential: "catalog.api_key"` reads
`api_key` below `catalog`. Every value is read as its text and converted like a command-line value, so `0123`, `no`
or `on` need no quotes; an empty value, `~` and `null` mean "not set". `edit` refuses to save invalid YAML and, on a
terminal, offers to edit again.

| Environment | File | Key |
|---|---|---|
| none | `.metacrunch/credentials.yml.enc` | `.metacrunch/master.key` |
| `-e production` or `METACRUNCH_ENV=production` | `.metacrunch/credentials.production.yml.enc` | `.metacrunch/master.production.key` |

[`examples/credentials`](../examples/credentials) has a runnable example. Each environment has its own file and key, so
laptops and CI need not hold the production key. A run with an
environment never falls back to the file without one.

- **Where:** `--credentials DIR` or `METACRUNCH_CREDENTIALS`, else the nearest `.metacrunch/` above the job file
  (for a job or command run by name: above the project's `Metacrunchfile`), else `~/.metacrunch/` for personal
  credentials. The directory found decides alone; `-v` logs the file that was decrypted. `metacrunch credentials`
  looks above the working directory and uses `~/.metacrunch/` only with `--credentials ~/.metacrunch`.
- **Key:** `METACRUNCH_MASTER_KEY`, else the key file. In containers and CI, set `METACRUNCH_MASTER_KEY`; with Kamal,
  list it under `env: secret:` and provide it in `.kamal/secrets`.
- **Order:** a parameter's value comes from the command line, a params file, its `env:` variable, the credentials,
  then the default, so an environment variable overrides a credential. Credentials are decrypted only if a value is
  needed: a container that sets every variable needs neither key nor file. Leave out `env:` to make sure that no
  inherited variable overrides a secret.
- **Params files:** a value `{credential: PATH}` in a params file (see
  [Parameter files](jobs.md#parameter-files)) takes the value from these credentials, for any parameter; the value is
  then hidden like a secret. `-e` selects the credentials and the section of the params file alike.
- **Secrets:** a parameter with `credential:` is secret. `--help`, error messages and `params.inspect` hide its value,
  and a value on the command line, where `ps` and the shell history show it, gives a warning. What a job does with the
  value, such as logging it or putting it into an exception, is not hidden. `Metacrunch::Testing.run` never reads
  credentials; pass values with `params:`.
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
