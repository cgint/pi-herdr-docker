# AGENTS.md — pi-agent-docker

## Purpose

Docker recipes for running `pi` (coding agent) and `herdr` (tmux-like pane
manager) in containers on macOS (Docker Desktop). Two workflows:

1. **`run.sh`** — single pi, one-off session.
2. **`herdr.sh`** — headless herdr server + N pi agent panes, persistent state.

North star: the host terminal is a thin CLI/TUI surface over containers.
No "pinching through docker" — `./herdr.sh attach` gets you to the TUI.

## Repo layout

| Path | What |
|---|---|
| `Dockerfile` / `Dockerfile.herdr` | Image builds (node:22-trixie base) |
| `run.sh` / `herdr.sh` | User-facing entry points |
| `docker-compose.herdr.yml` | Herdr container config |
| `herdr-config.toml` | Herdr UI prefs (mounted read-only into container) |
| `README.md` | User-facing docs (both workflows) |
| `NOTES.md` | Verified findings, rejected approaches, future ideas |
| `docs/herdr-web-ui-on-top.md` | **Planned** herdr-web bridge architecture |
| `agent/` | Agent-internal handoff briefs (private, not repo memory) |
| `vendor/` | Bundled binaries (herdr-web x86_64, ignored by git) |

## Durable pairing memory

**Durable pairing memory** is repository-owned, filesystem-persisted knowledge
that helps future agents continue collaborating with the user without losing
intent, decisions, terminology, constraints, or open loops. Remembering is
complete only after the appropriate filesystem artifact is updated. Chat
history, acknowledgment, or an intention to write later do not count.

### Stewardship

Agents are assigned the **authority, responsibility, and accountability** to
steward durable pairing memory: proactively organize, maintain, connect,
correct, and prune it while collaborating with the user. This does not imply
ownership or permission to bypass read-only, privacy, safety, or approval
boundaries.

Memory is **future-oriented curation**, not a record of what felt important
in the current session. Judge candidates by expected future usefulness.

### Selection test (FUTURE → CONSEQUENCE → ESSENCE → HOME)

- **Future:** Who could use this later, and in what situation?
- **Consequence:** What decision, action, mistake, or costly rediscovery
  could it affect?
- **Essence:** What is the smallest stable statement that preserves that value?
- **Home:** What is the narrowest canonical artifact that owns it?

Proactively persist verified information that passes this test. If no
concrete future use can be named, leave it transient. User statements like
"remember this" or "take note" are immediate persistence triggers.

### Memory checkpoint

Before completing meaningful work: identify durable findings, persist them
in their canonical home, update pointers, correct or prune stale memory.
Trivial chat or work with no durable findings requires no update. Routine
memory maintenance does not require separate permission. If persistence is
blocked, report **not persisted**.

## Canonical memory homes

| What | Home |
|---|---|
| Repo purpose, startup routine, key pointers, open loops | `AGENTS.md` (this file) |
| User-facing workflow docs | `README.md` |
| Verified technical findings, rejected approaches, ideas | `NOTES.md` |
| Planned architectures (not yet implemented) | `docs/` |
| Agent-internal handoff briefs, scratch, private evidence | `agent/` (not repo memory) |
| Current build/image status | `NOTES.md` § "Current state" (below) |

## Startup routine (for future sessions)

1. Read this file.
2. Read `README.md` for the two workflows.
3. Read `NOTES.md` § "Verified Findings" — especially macOS Docker Desktop
   filesystem limitations (sockets, atomic writes) and pi extension
   resolution. These are the facts most likely to cause a future session
   to waste time re-discovering.
4. Check `git status` and the "Current state" section below before assuming
   what is committed. This repo is public (MIT licensed) — treat
   uncommitted changes as potentially publishable.

## Key constraints (do not rediscover)

- **macOS Docker Desktop:** unix sockets and `rename()` (atomic writes)
  fail on bind mounts. Use named volumes for herdr state.
- **Pi ≥ 0.84 requires Node ≥ 22.** Base image: `node:22-trixie`.
- **Pi package:** `@earendil-works/pi-coding-agent` (not the frozen
  `@mariozechner/pi-coding-agent`).
- **Herdr state** lives in named volume `pi-agent-herdr_herdr-state`.
  `HERDR_CONFIG_DIR` env var is not honored by herdr 0.9.1.
- **Herdr config** is `herdr-config.toml` in this repo (copied from host,
  self-contained). Not linked to `~/.config/herdr/`.
- **`./herdr.sh down`** is the correct shutdown (SIGTERM → clean socket
  cleanup). `herdr server stop` (API) kills the container.

## Current state (2026-10-09)

- Repo is **public-ready**: MIT licensed, security scan clean
  (gitleaks: 0 leaks across full history; trivy: 0 vulns).
- Herdr container workflow **works**: build, start, workspace create,
  agent start (pi), prompt round-trip, state persistence across
  down/up — all verified end-to-end.
- **Herdr-web bridge is implemented**: `Dockerfile.herdr-web` +
  `herdr-entrypoint-web.sh` + `docker-compose.herdr-web.yml`, built on
  top of the server image (additive; `HERDR_WEB=false` restores
  server-only behavior). Source pinned via
  `build-context/herdr-web-src/herdr-web-e9e01f9.tar.gz` (SHA256-pinned,
  MIT-licensed upstream).
- Pi version in image: 0.87.1 (from `@latest` at build time).
- Herdr version: 0.9.1 (pinned, sha256-checked).
- **User Switch Plan (WIP, see `NOTES.md`):** container currently runs as
  root; the plan to run as a named user (host UID/GID) is documented but
  not yet implemented. `herdr.sh` already uses `/Users/cgint/...`
  container mount paths as a stepping stone; `docker-compose.herdr.yml`
  still uses the old `/root/...` paths — the two are inconsistent until
  the plan lands.
- **Open:** pi version pinning (currently `@latest`), local LLM
  reachability (ollama gateway untested from container),
  `session-history.json` secrets risk (pane_history=true).

## Open questions / next steps

1. **Finish the User Switch Plan** (`NOTES.md`) — switch container from
   root to named user; reconcile `herdr.sh` and `docker-compose.herdr.yml`
   mount paths in the same change.
2. **Pin pi version** in Dockerfile.herdr (currently `@latest`).
3. **Local LLM** — test `OLLA_BASE_URL` reachability from container when
   the gateway is running.
4. **Multi-container** — one herdr container per repo, for parallel work.
