# Host platform

## macOS Docker Desktop filesystem limitations drive several design choices

**Id:** 92656033-3943-4a41-9a37-b5d00ec8bcc5
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** Docker Desktop's macOS filesystem backend changes — **TRIGGERED 2026-10-24, see the superseding evidence at the end of this entry.**

Several decisions in this project exist because of verified limitations of macOS Docker Desktop's gRPC-Fuse bind-mount implementation, not because they are the ideal choice in general:

- Unix domain sockets cannot be created on bind mounts, and existing socket files cannot be removed from the host side.
- Atomic file writes (rename over an existing file) silently fail on bind mounts.
- Ordinary file creation and reading/writing work fine on bind mounts.
- Docker named volumes are real Linux filesystems inside the Docker VM and have none of these limitations.

**Reason:** these behaviors were each verified directly (a failing `bind()`, a failing `unlink()` on a socket, herdr starting but never persisting state) before the workarounds were adopted, rather than assumed from documentation.

**Consequence:** the "use a named volume for anything that needs a socket or an atomic write, bind-mount only what genuinely needs to be a host path" rule in this project is specific to this host's platform. Moving to a platform without these limitations (Linux host, or a newer Docker Desktop backend) lifts several of the constraints recorded in the herdr state and mount entries — those entries' `Revisit when` conditions exist for exactly this.

**See:** herdr-state.md — 8df98718-04bf-4ac1-8b60-df6d70252503 — as of 2026-10-10

## 2026-10-24 — the backend did change; the constraint is now unproven

**Status:** superseded (pending one end-to-end check)
**Evidence:** verified directly — Docker Desktop release notes quoted verbatim plus a
live `bind()`/`connect()`/`rename()`/`unlink()` test across a binder mount.

- Docker Desktop **4.80.0 (2026-06-29)** removed legacy osxfs (users migrated to VirtioFS).
- Docker Desktop **4.86.0 (2026-08-10)**: "AF_UNIX sockets shared over VirtioFS now work
  in both directions (host to guest and guest to host)."
- Re-test on this host, socket + atomic write across a bind mount: all four operations
  succeeded (`bind on bind-mount: OK`, `connect: OK`, `rename-over: OK`, `unlink: OK`).

**Why this entry is not deleted:** the original failure was real and specific to the
osxfs backend; keeping it prevents a future agent from re-deriving why the named
volume exists and wondering whether it was cargo cult. The gRPC-Fuse → VirtioFS change
is exactly the "revisit when" condition this entry named.

**Consequence:** the named-volume rule is now a *hypothesis under test*, not a
constraint. It stays in place until herdr itself is proven on a bind-mounted state
directory (sockets plus repeated atomic `session.json` writes across a down/up cycle).
Only that test — not the primitive test — justifies changing `herdr.sh`,
`docker-compose.herdr.yml`, `context/herdr-state.md` or the `AGENTS.md` key constraint.

**Verified-by:** lead, 2026-10-24. Details in `NOTES.md` § "Bind-mount socket/rename
re-test (2026-10-24)" and `agent/research/SYNTHESIS.md` § 1.1.
