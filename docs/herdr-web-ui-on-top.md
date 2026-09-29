# herdr-web-ui on top of Dockerfile.herdr

Status: **planned, not implemented** (reviewed via criticalthink + external advisor, 2026-09-29).
Base artifacts: `Dockerfile.herdr` (→ `pi-agent-herdr:node22`), `docker-compose.herdr.yml`,
`herdr.sh`, `herdr-entrypoint.sh`.

## Goal

Spin up one Docker container that contains the full stack:

```
Browser ── http://127.0.0.1:8787 ──▶ herdr-web-bridge ── unix socket ──▶ herdr server (PID1 tree)
                                                                            ├─ pi agent pane ×N
                                                                            └─ shells
volumes: ~/.pi (bind, rw) · repo (bind, rw) · herdr-state (named volume)
```

Web UI = `kcosr/herdr-web` (React client + Rust `herdr-web-bridge`), the same bundle already
proven on pluto (`pluto:/home/cgint/herdr-web`, v0.5.0 compose recipe).

## Architecture decision (post-review): single container, two supervised processes

Run `herdr server` and `herdr-web-bridge` inside **one** container via a supervised entrypoint,
not as two compose services.

Why (both independent reviews converged):
- **No socket/permission friction:** bridge talks to the container-local `herdr.sock`; no
  cross-container volume, no UID/GID mismatch under `HOME=/tmp/home`, no healthcheck-on-socket.
- **No path translation:** bridge `--upload-dir` and pi see the same absolute paths natively.
- Blast-radius of a process split buys nothing at personal-fleet scale.

Revised from the original two-service plan during review; the named `herdr-state` volume stays on
the **server** side (see State) even though the socket itself is container-local.

### Entrypoint supervision requirements

`herdr-entrypoint.sh` currently only `rm -f`s stale sockets before `exec "$@"`. It must become a
real supervisor:

- start `herdr server` and the bridge as children;
- forward SIGTERM/SIGINT to **both**, including on a second signal (no orphaned server on
  `docker stop`); `init: true` alone does not supervise children;
- stale-socket cleanup retained before server start;
- bridge must survive server restarts and vice versa (at minimum `restart`-the-dying-child or
  accept degraded UI until next poll — decide during implementation; the pluto experience shows
  bridge restart never interrupts panes).

Alternative supervisors if the shell version gets ugly: s6-overlay or supervisord. Reject naive
`cmd1 & cmd2 & wait` without signal forwarding.

## Bridge binary: build from source, multi-stage

Upstream `kcosr/herdr-web` ships **only** `linux-x86_64` + macOS artifacts — no linux-arm64.
Host Docker is aarch64. Decision: compile in a build stage.

- Repo layout verified: `bridge/Cargo.toml` (axum/ws, tokio, tower-http, interprocess via
  `vendor/herdr-compat`) + `web/` (TypeScript, ~119 files, npm).
- New stage in `Dockerfile.herdr`:
  `ARG HERDR_WEB_COMMIT` (pinned, protocol-matching) → `rust:<ver>-slim` builder (+ node for the
  web build) → copy `target/release/herdr-web-bridge` and built web assets into the runtime image
  at `/opt/herdr-web/` mirroring the vendor tarball layout (`bin/`, `share/herdr-web/web/`).
- **Do not** ship `platform: linux/amd64` emulation as the destination; it is a temporary probe
  only (see gates).

### Bridge launch (adapted from pluto's proven command line)

```
/opt/herdr-web/bin/herdr-web-bridge \
  --host 0.0.0.0 --port 8787 \
  --static-dir /opt/herdr-web/share/herdr-web/web \
  --upload-dir /opt/herdr-web/state/uploads \
  --allow-host localhost --allow-host <Mac-LAN-ip-or-tailscale-ip> \
  --allow-origin http://localhost:8787
```

with `HERDR_SOCKET_PATH` pointed at the container-local server socket, and
`HOME`/`XDG_DATA_HOME` set so the bridge's state (notes, agent-pins, log — see
pluto `state/` dir) lands on the state volume.

## State model

- **herdr server state** (workspaces, session metadata, plugins, pi integration): named volume
  (`pi-agent-herdr_herdr-state` already exists from earlier experiments — reuse it). `HERDR_CONFIG_DIR`
  is **not honored by 0.9.1** (verified); state path is derived from `HOME`, so point `HOME` at the
  volume mount, not `/tmp/home`, for the server.
- **Unix socket:** stays container-local (tmpfs or writable layer). Sockets do **not** work over
  macOS bind mounts; no need to share it once the bridge is in-container.
- **Pi state:** `~/.pi` bind-mounted read-write (unchanged). Sessions/auth/settings survive; live
  PTYs die with the container (accepted; re-`herdr agent start` on recreate).
- **Uploads:** container-local under the bridge's state dir; if pi must consume uploaded files,
  mount the uploads dir where the repo/workspace can see it — decide at implementation, note in
  compose comment.

## Security

- Publish `127.0.0.1:8787:8787` only. The bridge has **no user authentication**; Host/Origin
  checks are DNS-rebinding/CSRF mitigation, not auth. **Web access = shell access into pi panes.**
- Phone/LAN access: bind/publish via the **Tailscale interface IP explicitly** (or put an auth'd
  TLS gateway in front). Never `0.0.0.0` on a public interface.

## Version pairing (hard constraint)

- herdr 0.9.1 → terminal protocol **22** (verified via `herdr status` on host).
- herdr-web bridge requires protocol **exactly 22** and herdr ≥ 0.9.0 (vendor tarball README,
  upstream README). Vendored `herdr-compat` = private protocol code.
- Upgrade herdr and the bridge as one tested pair; pin `HERDR_WEB_COMMIT` to the commit whose
  protocol matches the pinned herdr.
- Bridge v0.6.1 is the current upstream release; v0.5.0 is the pluto-proven one.

## Verified facts (this session)

- Bridge never spawns the `herdr` CLI: `grep Command::new` across `bridge/src/*.rs` → no matches;
  launchers send argv through the socket API as layout command nodes with optional `agent_hint`
  (`bridge/src/launcher_presets.rs`). So the bridge only needs socket + state paths.
- `vendor/herdr-compat` deps: bincode, crossterm, interprocess, ratatui — pure Rust, favorable
  odds for an arm64 cross-compile of the same code upstream builds for amd64.
- Docker Desktop daemon: aarch64, buildx with arm64+amd64 platforms available.
- Image `pi-agent-herdr:node22` builds clean (node:22-trixie; bullseye packages purged upstream).

## Known unknowns

1. **From-source bridge build on arm64 unproven.** First gate. Stop-signal: if `interprocess` /
   vendored protocol code refuses to compile, fall back to (a) one-time qemu probe of the amd64
   binary's `--help` then vendor-bundle under emulation only for flag confirmation, or (b) run the
   bridge natively on the host Mac (macOS arm64 artifact exists) against a published TCP bridge.
2. **Exact bridge CLI flag surface** unverifiable locally (vendored binary is x86_64 ELF on
   arm64 — `--help` unrunnable). Flags above come from upstream README + pluto's working compose.
   First implementation step: read `bridge/src/main.rs` arg parsing, or probe once via
   `docker run --platform linux/amd64 … --help` (binfmt).
3. **`herdr integration install pi` durability:** writes into the herdr state dir (profile
   extension) — must land on the named volume; bake at build time into a skel dir + entrypoint
   copy, or run once via `herdr.sh exec`. Verify pane lifecycle state appears in the web sidebar.

## Implementation gates (ordered)

1. `docker run --platform linux/amd64 vendor-bridge --help` (or source read) → confirm flags.
2. Multi-stage build of bridge from pinned commit on arm64 → `/opt/herdr-web/` in image.
3. Single-container entrypoint supervision; `docker stop` leaves no stale sockets; bridge
   restart does not interrupt panes.
4. Browser `http://localhost:8787` → snapshot renders; launch two pi panes via built-in pi
   launcher; type/resize/scroll; agent status flips working/done.
5. Loopback hold: `curl <Mac-LAN-ip>:8787` from another box fails.
6. `docker compose down && up` → workspaces/plugins/integration survive via the state volume
   (panes legitimately gone; agents restartable).

## Out of scope / non-goals

- No per-agent container isolation (all panes share repo/UID/~/.pi — trusted personal fleet).
- No auth in the bridge; no TLS termination (gateway/Tailscale is the answer if ever needed).
- Keep the host `herdr` CLI workflow (`./herdr.sh attach|exec …`) as the primary control path;
  web UI is additive.
