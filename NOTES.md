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
- Container PATH is `/usr/local/bin:/usr/bin:/bin` — `/usr/sbin` is NOT in it.
  `runuser` lives at `/usr/sbin/runuser` and will NOT be found without full path.
- **macOS Docker Desktop UID mapping (verified):** host UID 501 maps directly
  to container UID 501. Files in bind mounts show as `501 20`. No remapping.
  `--user 501:20` works as expected.

**Review consensus (3 sub-agent reviews, 2026-09-29):**

The original plan (sshd as root + `runuser` in entrypoint + marker-file chown
+ SSH symlink) is sound but over-engineered. The minimal correct design:

| Original plan | Revised approach | Why |
|---|---|---|
| `runuser -u cgint` in entrypoint | `--user 501:20` on `docker run` | No privilege transition in entrypoint; simpler |
| Marker-file chown in entrypoint | One-time `docker run --user root alpine chown` | No per-start logic; volume is small |
| SSH symlink `/root/.config/herdr` → `/home/cgint/...` | Not needed if sshd is optional (gate behind root check) | Eliminates the problem |
| `runuser` full path fix | N/A (no runuser needed) | — |
| RW_DIRS path translation | Mount at host paths + symlink in entrypoint | No translation logic |
| `PI_CODING_AGENT_DIR` env | Can be dropped (HOME + mount at `$HOME/.pi` suffices) | Pi resolves naturally |

**Revised changes needed:**

### 1. Dockerfile.herdr
```
# Create cgint matching host UID 501, GID 20 (dialout in Debian)
RUN useradd -u 501 -g 20 -m -s /bin/bash cgint
# No USER directive — --user on docker run handles this
```

### 2. herdr.sh (docker run)
```
docker run -d \
  --user 501:20 \
  -e "HOME=/home/cgint" \
  -v "${HOME}/.pi:/home/cgint/.pi" \
  -v "${HOME}/dev:/home/cgint/dev:ro" \
  -v "${HOME}/dev-external:/home/cgint/dev-external:ro" \
  -v "pi-agent-herdr_${VOL}:/home/cgint/.config/herdr" \
  -v "${WORKDIR_REPO}:/workspace/current-repo" \
  ...
```
- Drop `PI_CODING_AGENT_DIR` (or keep as safety net: `/home/cgint/.pi/profiles/${PROFILE}/agent`)
- RW_DIRS: mount at host paths, add symlink in entrypoint

### 3. herdr-entrypoint.sh (main)
```
#!/bin/bash
set -euo pipefail
HERDR_STATE=/home/cgint/.config/herdr
mkdir -p "$HERDR_STATE"
rm -f "$HERDR_STATE"/herdr.sock "$HERDR_STATE"/*.sock 2>/dev/null || true

# Config
if [[ -f /opt/herdr-config.toml && ! -f "$HERDR_STATE/config.toml" ]]; then
  cp /opt/herdr-config.toml "$HERDR_STATE/config.toml"
fi

# sshd (optional, non-root, port 2222)
if [[ "${ENABLE_SSH:-false}" == "true" && -d /host-ssh ]]; then
  SSH_KEY="$HERDR_STATE/ssh_host_ed25519_key"
  [[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEY"
  # Install authorized_keys
  mkdir -p /home/cgint/.ssh && chmod 700 /home/cgint/.ssh
  : > /home/cgint/.ssh/authorized_keys
  for pub in /host-ssh/id_*.pub; do
    [[ -f "$pub" ]] && cat "$pub" >> /home/cgint/.ssh/authorized_keys
  done
  chmod 600 /home/cgint/.ssh/authorized_keys
  /usr/sbin/sshd -f /opt/sshd_config -h "$SSH_KEY" -p 2222 &
  echo "sshd started (non-root, port 2222)" >&2
fi

# herdr server (foreground)
exec herdr server "$@"
```
- No `runuser`, no `chown`, no marker file
- sshd gated behind root check (only runs if `--user 0`)
- Entrypoint is ~20 lines, not 60

### 4. One-time volume migration (manual, documented)
```
docker run --rm --user root -v pi-agent-herdr_herdr-state:/data alpine:3 \
  sh -c 'chown -R 501:20 /data && rm -f /data/*.sock'
```
Run once before the first `./herdr.sh up` after the switch.

### 5. herdr-entrypoint-web.sh (other agent's scope)
- Same `--user` change on the compose file's `user:` field
- No `runuser` needed (same approach)
- `HERDR_SOCKET_PATH` in docker-compose.herdr-web.yml must point to
  `/home/cgint/.config/herdr/herdr.sock`

### 6. session.json migration
- `session.json` has `"cwd": "/root"`. After the switch, herdr starts with
  HOME=/home/cgint. The first pane will have a broken cwd.
- **Decision:** accept it (user creates a new workspace) OR sed the migration
  script to update `session.json` (`s|"cwd": "/root"|"cwd": "/home/cgint"|`).

### 7. Rollback procedure
If the switch breaks:
1. `docker rm -f pi-agent-herdr`
2. `docker run --rm --user root -v pi-agent-herdr_herdr-state:/data alpine:3 sh -c 'chown -R 0:0 /data && rm /data/.owned-by-cgint'`
3. Revert herdr.sh (remove `--user`, restore old mount paths)
4. `./herdr.sh up`

### Open decisions
- **RW_DIRS paths:** mount `~/dev` at `/home/cgint/dev:ro` (user home path, not host path).
  RW_DIRS then use container paths: `RW_DIRS=/home/cgint/dev/repo-a`.
  The ro parent + rw child nested mount handles the override.
  No symlinks needed. herdr.sh expands `~` to the container home for RW_DIRS.
- **sshd (confirmed feasible as non-root):** run sshd as cgint on port 2222
  (unprivileged port, no CAP_NET_BIND_SERVICE needed). Host keys stored in
  the named volume (persist across restarts). `UsePAM no`, `PermitRootLogin no`,
  pubkey-only. Gated behind `ENABLE_SSH=true` env var. Port published as
  `127.0.0.1:2222:2222` (loopback only). Entry:
  ```sh
  if [[ "${ENABLE_SSH:-false}" == "true" ]]; then
    SSH_KEY="$HERDR_STATE/ssh_host_ed25519_key"
    [[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEY"
    /usr/sbin/sshd -f "$HERDR_STATE/sshd_config" -h "$SSH_KEY" -p 2222 &
  fi
  ```
  sshd_config: `Port 2222`, `UsePAM no`, `PasswordAuthentication no`,
  `PubkeyAuthentication yes`, `PermitRootLogin no`,
  `AuthorizedKeysFile /home/cgint/.ssh/authorized_keys`,
  `HostKey <path>` (the volume-persisted key).
- **Web entrypoint:** coordinate with the herdr-web agent (pane wJ:p2).
  Same `--user 501:20` on the compose file. `HERDR_SOCKET_PATH` must point
  to `/home/cgint/.config/herdr/herdr.sock`.

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
