# herdr-web-ui on top of Dockerfile.herdr

Status: **IMPLEMENTED 2026-09-29** as an ADDITIVE companion (existing container definition
untouched): `Dockerfile.herdr-web` (stacks `FROM pi-agent-herdr:node22`; builds the bridge
natively for arm64 from the pinned v0.6.1 tarball + vite UI), `docker-compose.herdr-web.yml`
(shares the `herdr-state` volume; loopback-only `127.0.0.1:8787`), `herdr-entrypoint-web.sh`
(supervised: server first, then bridge gated on the socket; HERDR_WEB=false restores plain
server behavior), and `./herdr.sh up-web|web-url|web-log|attach-web`. Verified live: HTTP 200
UI, `/api/snapshot` sees panes, `pane run` output visible, `agent start --kind pi` + prompt
round-trip answered. Two deviations from this plan, both deliberate: (1) order is
server->bridge because the v0.6.1 bridge hard-fails when the daemon socket is absent at
startup (`startup_daemon_status` probes before binding) — the bridge still stays up for the
server's whole lifetime; (2) `--allow-host` values must be bare hostnames (no ports) per
v0.6.1 `normalize_allowed_host`, so loopback Host entries are covered by the bridge's builtin
loopback allowance and an optional `WEB_ALLOW_HOST` passthrough handles a custom DNS name.
Original review trail: (reviewed via criticalthink + external advisor; claims
cross-checked via doc-rocker MCP through `npx mcporter` by independent worker Konrad,
2026-09-29 — see "Cross-check results" at the bottom).
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
proven on a Linux host (`/home/cgint/herdr-web`, v0.5.0 compose recipe).

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

- Publish `127.0.0.1:8787:8787` only. The bridge has **no user authentication** (verified at
  `web_bridge.rs:985` on upstream main: "herdr-web-bridge has no browser authentication yet;
  bind only on trusted networks"; README: Host/Origin checks are "a DNS-rebinding/CSRF guard,
  not user authentication"). **Web access = shell access into pi panes.** Bridge-owned notes
  are readable/mutable by any allowed client — no sensitive notes on a LAN-bound bridge.
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
   Cross-check caveat: lifecycle state (working/idle/blocked) is confirmed, but **"native session
   restore for pi panes" is not confirmed by sourced docs** — doc-rocker found sources denying
   it; herdr 0.9.2's agent self-reported resume commands may change this. Treat pi session
   continuity as riding on pi's own `~/.pi` session files, not on herdr restore.

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

## Cross-check results (doc-rocker MCP via npx mcporter, worker Konrad, 2026-09-29)

MCP discovery: ad-hoc inline-URL mode — `npx mcporter call 'https://doc-rocker.com/api/mcp'
<tool> k=v ...`. Real endpoint is `POST /api/mcp` (root and `/mcp` 404/406). Tools:
`search_documentation(query, domains[])` (AI-combined web search; **rate limit 2/min, 30/day per
egress IP**; the `youshallnotpass` bypass header applies only to `api_chat`/`api_rock`, verified
in `rate_limiter.ex`), `list_documentation_sources()`.

| Claim | Verdict | Basis |
|---|---|---|
| C1 protocol 22 pairing | CONFIRMED | host `herdr status server` → `private_protocol: 22`; upstream README + vendored README. An interim doc-rocker "protocol 8" contradiction was a **combiner artifact** (misattributed a v0.5.12-era changelog line to 0.9.1); primary changelog has no 0.9.1 protocol bump |
| C2 no linux-arm64 bridge | CONFIRMED | upstream README platform list: linux-x86_64 + macOS only; herdr itself does ship linux-aarch64 |
| C3 HERDR_CONFIG_DIR not honored | CONFIRMED | doc-rocker: undocumented/unrecognized, state under HOME; corroborated by NOTES.md |
| C4 bridge never spawns herdr CLI | UNDETERMINED (doc-rocker) | no corpus; plan's upstream-source grep stands as the evidence |
| C5 no bridge auth | CONFIRMED | doc-rocker's CONTRADICTED verdict (`--auth` flag with form/local/auto/native modes) did **not reproduce**: zero `auth` hits in v0.6.1 bridge sources; upstream main says explicitly "no browser authentication yet" (web_bridge.rs:985). Rejected as combiner hallucination/version-confusion |
| C6 tmux-like server owns PTYs | CONFIRMED | doc-rocker + host `herdr status` (socket under sessions dir) |
| C7 pi integration | CONFIRMED, one clause downgraded | `integration install pi` + lifecycle states confirmed; **"native session restore for pi panes" unsupported** — amended above |
| C8 unix sockets on macOS bind mounts | CONFIRMED | Docker forums 142653 / desktop-feedback#279 via doc-rocker; named volumes = reliable; in-container socket = valid alternative (our choice) |

**Method warning learned:** doc-rocker answers are AI-combined web search (lite model) with
citation links; it fabricated a flag surface and misattributed changelog lines. For
version-specific claims, fetch primary text (raw GitHub) — done for every contested verdict.

## Out of scope / non-goals

- No per-agent container isolation (all panes share repo/UID/~/.pi — trusted personal fleet).
- No auth in the bridge; no TLS termination (gateway/Tailscale is the answer if ever needed).
- Keep the host `herdr` CLI workflow (`./herdr.sh attach|exec …`) as the primary control path;
  web UI is additive.
