# pi-agent-docker

A small Docker image for running `pi` with common CLI tools preinstalled.

## Tools included

- `pi` (from `@mariozechner/pi-coding-agent`)
- `rg` (ripgrep)
- `fd`
- `uv`, `uvx`
- `d2`
- `git`, `jq`, `curl`

## Build

```bash
cd ~/dev-external/pi-agent-docker
./build.sh
```

You can override the d2 version:

```bash
D2_VERSION=0.6.9 ./build.sh
```

## Run

From any repo you want to work in:

```bash
~/dev-external/pi-agent-docker/run.sh --profile partner
```

By default the repo is mounted read-only, with `docs/`, `openspec/` and `.pi/` mounted read-write (if they exist).

To add additional writable directories:

```bash
~/dev-external/pi-agent-docker/run.sh --rw tmp --rw test
```

## Why mount both ~/.pi/agent and profile dir?

Some profiles use symlinks like:

```
auth.json -> ../../../agent/auth.json
```

Mounting `~/.pi/agent` to `/pi/agent` preserves that symlink resolution in the container.
