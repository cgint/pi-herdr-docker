# Docker + Herdr + Pi: Findings, Requirements, Ideas

## Current state (2026-09-29)

- **Working:** herdr container build → start → workspace create → pi agent
  start → prompt round-trip → state persists across `down`/`up`.
- **Pi in image:** `@latest` (0.87.1 at last build — not pinned).
- **Herdr in image:** 0.9.2 (pinned, sha256-checked, protocol 22).
- **Base image:** `node:22-trixie`.
- **User in container:** root (UID 0, GID 0).
- **Git:** committed through `f39a2c6`. Untracked: herdr-web files (other agent).
- **Next:** switch to named user (see below), pin pi version, herdr-web bridge
  (see `docs/herdr-web-ui-on-top.md`), local LLM test.

## User Switch Plan (cgint, UID 501, GID 20)

**Goal:** run the container as `cgint` (matching host UID/GID) so files written
into mounted dirs are owned correctly. `~/dev` and `~/dev-external` mounted
under the user's home at their host paths.

**Host facts (verified 2026-09-29):**
- `id -u cgint` = 501, `id -g cgint` = 20 (macOS `staff`)
- In Debian trixie, GID 20 is `dialout` (already exists). Do NOT `groupadd -g 20`.
- All files in `pi-agent-herdr_herdr-state` volume are `root:root` (UID 0).
- `/usr/local/bin/herdr` and `/usr/local/bin/pi` are world-executable (`-rwxr-xr-x`).
- `~/.pi/profiles/minimal/agent/` has two symlinks to `~/.pi/agent/`
  (`auth.json`, `models.json`). Keeping `~/.pi` mounted at a flat path
  (e.g. `/pi`) preserves these symlinks. Mounting only the profile dir
  breaks them (target `../../../agent/...` doesn't exist in the container).

**Changes needed:**

### 1. Dockerfile.herdr
```
# Create cgint matching host UID 501, GID 20 (dialout in Debian)
RUN useradd -u 501 -g 20 -m -s /bin/bash cgint
# Do NOT set USER cgint here — entrypoint needs root for sshd + chown
```
- Keep `USER root` (implicit default). The entrypoint drops to cgint via `runuser`.
- No other Dockerfile changes. npm global bins are world-executable.

### 2. herdr-entrypoint.sh (main)
```
# New: herdr state path
HERDR_STATE=/home/cgint/.config/herdr

# New: chown volume on first run (marker file avoids re-chown on every start)
if [[ ! -f "$HERDR_STATE/.owned-by-cgint" ]]; then
  chown -R 501:20 "$HERDR_STATE"
  touch "$HERDR_STATE/.owned-by-cgint"
  chown 501:20 "$HERDR_STATE/.owned-by-cgint"
fi

# Changed: authorized_keys path
mkdir -p /home/cgint/.ssh
chmod 700 /home/cgint/.ssh
# ... copy keys to /home/cgint/.ssh/authorized_keys ...
chown -R 501:20 /home/cgint/.ssh

# sshd config: point to the new authorized_keys path
# (or keep /root/.ssh if sshd runs as root and we put keys there)

# New: drop to cgint for herdr server
exec runuser -u cgint -- herdr server "$@"
```
- sshd still runs as root (port 22, host keys).
- `runuser` is available in Debian trixie (from `util-linux`).
- The chown is one-time (marker file). Subsequent starts skip it.

### 3. herdr-entrypoint-web.sh (other agent's scope)
- Same `runuser` change before `herdr server`.
- Same `HERDR_STATE` path change.
- Coordinate with the web agent before merging.

### 4. herdr.sh (docker run flags)
```
# Changed mounts:
-v "${HOME}/.pi:/home/cgint/.pi"              # was /pi
-v "${HOME}/dev:/home/cgint/dev:ro"           # was /Users/cgint/dev:ro
-v "${HOME}/dev-external:/home/cgint/dev-external:ro"
-v "pi-agent-herdr_${VOL}:/home/cgint/.config/herdr"  # was /root/.config/herdr

# Changed env:
-e "HOME=/home/cgint"
-e "PI_CODING_AGENT_DIR=/home/cgint/.pi/profiles/${PROFILE}/agent"
```
- `RW_DIRS` paths: still mount at host paths, but those paths now need to be
  under `/home/cgint/dev/...` for the ro parent to apply.
  Or: keep host paths and add a symlink `/home/cgint/dev → /Users/cgint/dev`.
  **Decision needed:** host paths vs user home paths for dev mounts.

### 5. docker-compose.herdr.yml (web mode)
- Same mount + env changes as herdr.sh.

### 6. SSH (herdr --remote)
- sshd runs as root, `PermitRootLogin prohibit-password` → login as root.
- But the herdr server runs as cgint, socket at `/home/cgint/.config/herdr/herdr.sock`.
- SSH session gets `HOME=/root` by default → herdr CLI looks for
  `/root/.config/herdr/herdr.sock` → **mismatch**.
- Fix: `UsePAM yes` + `UseShellEnvironment no` won't help.
  Set `AcceptEnv HOME` in sshd_config + client sends `HOME=/home/cgint`.
  Or: create `/root/.config/herdr` as a symlink to `/home/cgint/.config/herdr`.
  Or: change `PermitRootLogin` to `no`, force login as cgint only.
  **Simplest:** symlink. `ln -s /home/cgint/.config/herdr /root/.config/herdr`
  in the entrypoint.

### Risks / open questions
- **RW_DIRS with host paths:** if `~/dev` is mounted at `/home/cgint/dev:ro`,
  then `RW_DIRS=~/dev/repo-a` needs to be `/home/cgint/dev/repo-a` inside
  the container. The herdr.sh `docker run` would need to translate host paths
  to container paths. Or: mount at host paths AND add symlinks in the user home.
- **Volume migration:** existing volume has root-owned files. The one-time
  chown handles this, but if the volume grows large (many session snapshots),
  the chown takes time on first run after the switch.
- **Web entrypoint:** must be updated in lockstep. Coordinate with the
  herdr-web agent (pane wJ:p2).

## Verified Findings

### macOS Docker Desktop filesystem limitations

- **Unix domain sockets** cannot be created on macOS bind mounts. `bind()` fails with
  `EINVAL`, `unlink()` fails with `ENOTSUP` (gRPC-Fuse limitation).
- **Atomic file writes** (`rename()` over an existing file) silently fail on bind mounts.
  Herdr uses this pattern for `session.json` — when bind-mounted, herdr starts but
  never persists state (the rename fails, the original file is unchanged).
- **Regular file reads/writes** (create new, truncate, write) work fine on bind mounts.
- **Docker named volumes** are Linux filesystems inside the VM — sockets and atomic
  writes work normally. This is the only way to persist herdr state on macOS.
- **Volume naming**: Docker compose names volumes as `<project>_<volume>` where
  project defaults to the compose file's `name:` field (here: `pi-agent-herdr`).
  The actual volume is `pi-agent-herdr_herdr-state` (underscore, not hyphen).
  There is also an orphan empty volume `pi-agent-herdr-herdr-state` (hyphens) from
  an earlier experiment — safe to remove with `docker volume rm pi-agent-herdr-herdr-state`.

### Herdr (v0.9.1) state layout

| File | Contents | When written |
|---|---|---|
| `session.json` | Workspaces, tabs, panes, cwd, layout, focus | On state changes (workspace create, pane split, etc.) |
| `session-history.json` | Pane screen history (opt-in via `pane_history = true`) | On state changes |
| `sessions/<name>/` | Named persistent sessions | Per-session |
| `config.toml` | Keybindings, UI prefs, experimental flags | User-managed |
| `herdr.sock`, `herdr-client.sock` | Unix domain sockets | Server lifetime |
| `herdr-server.log`, `herdr-client.log` | Logs | Continuous |

- `HERDR_CONFIG_DIR` env var is **not honored** by v0.9.1. Herdr always uses
  `$HOME/.config/herdr`.
- `HOME` env var **is honored** — changing it moves the entire state dir.
- `herdr server stop` (API) exits the server process. If herdr is PID 1, the
  container dies. With `init: true` (tini), the container survives but herdr is dead.
- `docker compose down` sends SIGTERM → herdr cleans up socket → exits cleanly.
  This is the correct shutdown path (no stale sockets).

### Pi (coding agent) in Docker

- **Package name changed**: `@mariozechner/pi-coding-agent` (frozen at 0.73.1)
  → `@earendil-works/pi-coding-agent` (current: 0.87.1). The old name still
  installs but lacks knowledge of newer model IDs.
- **Node version**: pi ≥ 0.84 requires Node ≥ 22 (`fs.globSync`). Base image
  must be `node:22-*`.
- **Extension resolution**: pi extensions in `~/.pi/profiles/<name>/agent/extensions/`
  and `~/.pi/profiles/<name>/agent/git/.../` resolve `@earendil-works/*` packages
  by walking up the directory tree. If the profile has no `node_modules/` at the
  agent root, resolution falls through to the global npm install.
- **Extension deps**: the 6 git extensions under the profile each need their own
  `npm install` to populate `node_modules/@earendil-works/*`. On the host these
  were empty dirs (stale symlinks to `/opt/homebrew/...` that don't exist in
  the container). Fix: `npm install` in each extension dir + profile-agent root.
- **undici crash**: `@earendil-works/pi-coding-agent` bundles `undici@8.9.0`
  which requires Node 22 webidl internals. On Node 20 this crashes with
  `webidl.util.markAsUncloneable is not a function`. Resolved by using Node 22.
- **Model reachability from container**:
  - `anthropic/*` — works (key in `~/.pi/agent/auth.json`, cloud endpoint)
  - `home-llm/*` — local LLM servers on host loopback; unreachable as configured.
    Need `OLLA_BASE_URL=http://host.docker.internal:<port>` for the gateway.
  - `tensorfold-local` — `127.0.0.1:8080` = container loopback, not host.
    Would need `host.docker.internal:8080`.
  - `cerebras/*` — cloud, should work (key in auth.json).

### Herdr CLI (from skill file)

- `herdr agent prompt <target> "text" --wait` — waits for first settled
  `idle`/`done`/`blocked` state. **Do not add `--until`** for normal work;
  it narrows the wait and causes false timeouts (e.g. `--until done` misses
  the `idle` that pi settles into).
- `--until` is only for state-specific workflows (e.g. waiting for `blocked`).
- `herdr agent start <name> --kind pi --pane <id> -- <pi args>` — starts pi
  in an existing shell pane. The `--` separates herdr args from pi args.
- `herdr workspace create --cwd <path> --label <name>` — returns pane ID in
  `.result.root_pane.pane_id`.

## Requirements (user-stated)

1. **Avoid "pinching through docker"** — the host terminal should be a simple
   attach/CLI surface, not a sequence of `docker exec` commands.
2. **Pi read-write from `~/.pi/`** — auth, settings, profiles, sessions must
   persist on the host.
3. **Herdr state should persist** across container restarts (workspaces, panes,
   layout). User suggested "mount some dir from host" but the technical
   constraint (sockets) requires a named volume.
4. **Self-contained repo** — config files copied into the repo, not linked to
   `~/.config/herdr` or other host locations.
5. **Instant** — `./herdr.sh up` should just work, no manual steps.
6. **Named user (cgint, UID 501, GID 20)** — container runs as the host user,
   not root. Files written into mounted dirs must have matching UID/GID.
7. **`~/dev` and `~/dev-external` mounted read-only** at the user's home path.
   Specific subdirs can be overridden read-write via `RW_DIRS`.
8. **`~/.pi` mounted at a flat path** (not profile-nested) so symlinks inside
   the profile resolve correctly.

## Ideas / Future Work

### Done (2026-09-29)

- ~~README section for the herdr workflow~~ — written in `README.md`.
- ~~`herdr-config.toml` in repo~~ — done.
- ~~Named volume for herdr state~~ — done, verified across down/up.
- ~~AGENTS.md + pairing memory bootstrap~~ — done.

### Not yet done
- **Switch to named user (cgint, UID 501, GID 20)** — see plan below.
- **Multi-container**: run N containers, each with its own herdr session,
  for parallel pi agents on different repos. `herdr.sh -n <name>` works.
  but still runs as root (will change with the user switch).
- **`herdr.sh prompt` subcommand**: wrap `herdr agent prompt` with sensible
  defaults (`--wait`, no `--until`) so the user doesn't need to remember
  the herdr CLI syntax.
- **`herdr.sh new-workspace` subcommand**: wrap `herdr workspace create` +
  `herdr agent start` in one call.
- **Local LLM support**: if the ollama gateway is running on the host, set
  `OLLA_BASE_URL=http://host.docker.internal:40114` in the compose env.
  Currently the gateway is down, so this is untested.
- **Pi version pinning**: currently uses `@latest` in the Dockerfile. For
  reproducibility, pin to a specific version (e.g. `@0.87.1`) and update
  deliberately.
- **Herdr version pinning**: already pinned via `ARG HERDR_VERSION=0.9.1`
  with sha256 check. Good.
- **Session export/backup**: `docker cp` the volume contents for archival.
  No built-in herdr export command; `session.json` is plain JSON.
- **`session-history.json` secrets risk**: with `pane_history = true`, the
  history file contains terminal output (may include API keys, passwords).
  The named volume is inside the Docker VM (not directly accessible from the
  host), which is a mild mitigation. Consider `pane_history = false` in the
  container config if the risk is unacceptable.

### Rejected approaches (and why)

- **Bind-mount `~/.config/herdr`**: host herdr server uses those sockets
  while running → `EADDRINUSE` / double-server conflict.
- **Bind-mount `session.json` + `session-history.json` individually**:
  herdr's atomic write pattern (`rename()`) fails silently on macOS bind
  mounts. Herdr starts but never persists state.
- **Bind-mount `./herdr-state/` dir**: same socket + rename problem as above.
- **`HERDR_CONFIG_DIR` env var**: not honored by herdr v0.9.1.
- **Entrypoint script to clean stale sockets**: `rm` on a unix socket in a
  macOS bind mount returns `ENOTSUP`. Can't be done from inside the container.
- **`@mariozechner/pi-coding-agent`**: frozen at 0.73.1, doesn't know newer
  model IDs. Use `@earendil-works/pi-coding-agent`.
- **Node 20 base image**: pi ≥ 0.84 requires Node 22 (`fs.globSync`).
