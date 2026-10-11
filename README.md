[![Keep the Why](https://keepthewhy.com/assets/badge.svg)](https://keepthewhy.com)

# pi-herdr-docker

Docker recipes for running [`pi`](https://pi.dev) (a coding
agent) in containers on macOS, pre-packaged with the tools it needs.

**Why:** running a coding agent on your host means it executes untrusted code,
installs dependencies, and leaves state behind. These recipes move all of that
into a throwaway container: your host stays clean, the agent gets a full
environment (Node 22, git, ripgrep, uv, d2, ...), and your workspace is
mounted in read-only by default — you opt in to writable directories
explicitly.

**Two workflows:**

1. **Single pi, one-off session** (`run.sh`) — spin up one agent in a repo,
   work, discard the container. For quick tasks.
2. **Herdr + N pi agents** (`herdr.sh`) — a headless herdr server owning
   multiple persistent agent panes (tmux-like): attach/detach from the host
   terminal or a local web UI, state survives restarts. For parallel, ongoing
   work.

---

## Tools included (both images)

- `pi` (from `@earendil-works/pi-coding-agent`)
- `rg` (ripgrep)
- `fd`
- `uv`, `uvx`
- `d2`
- `git`, `jq`, `curl`
- `herdr` (herdr workflow only)

---

## Workflow 1: Single pi (`run.sh`)

### Build

```bash
./build.sh
```

Override d2 version: `D2_VERSION=0.6.9 ./build.sh`

### Run

From any repo you want to work in:

```bash
./run.sh --profile partner
```

By default the repo is mounted read-only, with `docs/`, `openspec/` and `.pi/`
mounted read-write (if they exist).

To add additional writable directories:

```bash
./run.sh --rw tmp --rw test
```

### Why mount both ~/.pi/agent and profile dir?

Some profiles use symlinks like:

```
auth.json -> ../../../agent/auth.json
```

Mounting `~/.pi/agent` to `/pi/agent` preserves that symlink resolution in the container.

---

## Workflow 2: Herdr + N pi agents (`herdr.sh`)

A headless herdr server runs in the container. You attach from the host with
`./herdr.sh attach` and control pi agents through the herdr CLI or TUI.

### Files

| File | Purpose |
|---|---|
| `Dockerfile.herdr` | node:22-trixie + pi + herdr + tools |
| `docker-compose.herdr.yml` | Volumes, env, named volume for herdr state |
| `herdr.sh` | up/attach/agent-list/status/stop/down/exec |
| `herdr-config.toml` | Herdr UI prefs (copied from host, editable here) |

### Quick start

```bash
# From the repo you want agents to work in:
WORKDIR_REPO=$PWD ./herdr.sh up

# Attach to the herdr TUI:
./herdr.sh attach

# Or from inside, create a workspace + start pi:
docker compose -f docker-compose.herdr.yml exec herdr \
  herdr workspace create --cwd /workspace/current-repo --label my-project
docker compose -f docker-compose.herdr.yml exec herdr \
  herdr agent start p1 --kind pi --pane w1:p1 -- --model anthropic/claude-opus-5-5

# Send a prompt:
docker compose -f docker-compose.herdr.yml exec herdr \
  herdr agent prompt p1 "Hello" --wait

# Stop and remove:
./herdr.sh down
```

### State persistence

- **Pi state** (`~/.pi`): bind-mounted read-write. Sessions, auth, model
  config persist on the host. Note: this mounts your **entire** `~/.pi`
  directory into the container — anything in it (auth tokens, session
  history, profile configs) is readable by the container process.
- **Herdr state** (workspaces, panes, layout): stored in a Docker named
  volume (`pi-agent-herdr_herdr-state`). Survives `./herdr.sh down && up`.
  Reset with `docker volume rm pi-agent-herdr_herdr-state`.
- **Herdr config**: `herdr-config.toml` in this repo, mounted read-only.
  Edit it here, not in `~/.config/herdr/`.

### Why a named volume for herdr state?

Unix domain sockets and atomic file writes (`rename()`) don't work on macOS
bind mounts (Docker Desktop gRPC-Fuse limitation). Herdr needs both. A named
volume is a Linux filesystem inside the Docker VM where these work normally.

See `NOTES.md` for the full investigation.

### Remote attach from the host (no `docker exec`)

Add this to your `~/.ssh/config` (once):

```ssh-config
Host pi-agent-herdr
  HostName localhost
  Port 2222
  User root
  StrictHostKeyChecking accept-new
```

Then:

```bash
./herdr.sh remote   # opens herdr TUI on the host, connected over SSH
```

This gives you the full herdr UI (mouse, workspaces, agent sidebar) running
on your host terminal, attached to the container's herdr server. Detach with
`ctrl+b q` — the server and agents keep running in the container.

### Env vars

| Var | Default | Purpose |
|---|---|---|
| `WORKDIR_REPO` | `$PWD` | Repo to mount at `/workspace/current-repo` |
| `PROFILE` | `minimal` | Pi profile (under `~/.pi/profiles/`) |
| `OLLA_BASE_URL` | `http://host.docker.internal:40114` | Local LLM gateway |
| `GEMINI_API_KEY` | _(empty)_ | Pass through from host env |

### Note: host-specific mount paths

`herdr.sh` mounts `~/dev` and `~/dev-external` at fixed in-container paths
(`/Users/cgint/dev`, `/Users/cgint/dev-external`) — these reflect the
author's macOS setup and are part of a work-in-progress migration to run
the container as a named user (see `NOTES.md` → "User Switch Plan"). If
your username differs, either adjust those two `-v` flags in `herdr.sh`
or rely on `RW_DIRS=...` for the directories you need writable.
