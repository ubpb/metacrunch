# Environments

An environment is the set of values a run uses: on a laptop, in CI, on the production server. metacrunch keeps
what differs between them out of the jobs: a job declares its parameters, and the
[params file](jobs.md#parameter-files) and the [credentials](credentials.md) of the selected environment give the
values.

## The default environment

A run without `-e` uses the default environment, named `default`. It needs no setup: a job runs with its defaults and
the values on the command line, and, if they exist, with `.metacrunch/credentials.yml.enc` and the `default:` section
of a params file. Most jobs never need another environment.

`default` is reserved: `-e default` and `METACRUNCH_ENV=default` fail, since leaving `-e` out says the same.

## Selecting an environment

```
$ metacrunch run -e production --params config/export.yml export.rb
```

`-e NAME` selects the environment for `run`, `check`, `trace` and `credentials`. Without `-e`, the variable
`METACRUNCH_ENV` selects it, which suits a server or container that always runs in one environment; give `-e` on the
command line wherever you can, so that every call says where it runs. A run logs where a selected environment comes
from: `environment production (from -e)` or `environment production (from METACRUNCH_ENV)`. Names are `a-z`, `0-9`,
`_` and `-`.

One call runs in one environment: the job named on the command line, the jobs and commands it invokes and the
transforms they use all read the same credentials. From Ruby, `Job#run(environment:)` and
`Project#invoke(environment:)` select it; without `environment:`, `METACRUNCH_ENV` of `env:` does.

## What belongs to an environment

| | `default` (no `-e`) | `production` (`-e production`) |
|---|---|---|
| Credentials file | `.metacrunch/credentials.yml.enc` | `.metacrunch/credentials.production.yml.enc` |
| Key | `.metacrunch/master.key` or `METACRUNCH_MASTER_KEY` | `.metacrunch/master.production.key` or `METACRUNCH_MASTER_KEY` |
| Params file section | `default:` | `production:` |

Every environment has its own credentials file and its own key, created with `metacrunch credentials edit -e
production`. A run in `production` reads only `credentials.production.yml.enc` and only the `production:` section of
the params file: it never falls back to the files or the section of the default environment. A value both need is
written into both, or shared in the params file with a YAML anchor (see [Parameter files](jobs.md#parameter-files)).
So the production key can stay on the production machines: a laptop with only `master.key` cannot read the
production credentials, and a run in `production` cannot pick up a development value by accident.

`METACRUNCH_MASTER_KEY` is the key of whatever environment a run selects. A machine that runs several environments
should keep one key file per environment instead.

## Examples

**Laptop.** The project has `.metacrunch/credentials.yml.enc` and `master.key` (gitignored) for development, and
`credentials.production.yml.enc` without its key:

```
$ metacrunch run export.rb                                           # the default environment
$ metacrunch run -e production --params config/export.yml export.rb  # fails at the first production credential
```

The second call fails as soon as a value refers to a production credential: there is no `master.production.key`.

**CI.** CI checks one environment per call, with that environment's key in `METACRUNCH_MASTER_KEY`:

```
$ METACRUNCH_MASTER_KEY=$PRODUCTION_KEY metacrunch check -e production --params config/export.yml export.rb
```

`check` checks every section of the params file for unknown keys and invalid plain values without any key; it
resolves the references, and so needs the key, only for the selected environment.

**Container (Kamal).** The orchestrator hands secrets over as environment variables, so the container's section of
the params file refers to them, and the container needs neither a key nor a credentials file:

```yaml
# config/export.yml
container:
  es_url: {env: ES_URL}
  api_key: {env: CATALOG_API_KEY}
```

```
$ metacrunch run -e container --params config/export.yml export.rb
```

With Kamal, list `ES_URL` and `CATALOG_API_KEY` under `env: secret:` and provide them in `.kamal/secrets`. A
container that should read the encrypted credentials instead gets `METACRUNCH_MASTER_KEY` that way.
