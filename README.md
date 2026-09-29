# pi-agent-docker

Docker images for running `pi` (coding agent) with common CLI tools.

Two workflows:

1. **Single pi in a container** (`run.sh`) — the original, for quick one-off pi sessions.
2. **Herdr + N pi agents** (`herdr.sh`) — a headless herdr server in a container
   owning multiple pi agent panes, with persistent herdr state.

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
  config persist on the host.
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
