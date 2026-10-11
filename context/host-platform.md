# Host platform

## macOS Docker Desktop filesystem limitations drive several design choices

**Id:** 92656033-3943-4a41-9a37-b5d00ec8bcc5
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** Docker Desktop's macOS filesystem backend changes

Several decisions in this project exist because of verified limitations of macOS Docker Desktop's gRPC-Fuse bind-mount implementation, not because they are the ideal choice in general:

- Unix domain sockets cannot be created on bind mounts, and existing socket files cannot be removed from the host side.
- Atomic file writes (rename over an existing file) silently fail on bind mounts.
- Ordinary file creation and reading/writing work fine on bind mounts.
- Docker named volumes are real Linux filesystems inside the Docker VM and have none of these limitations.

**Reason:** these behaviors were each verified directly (a failing `bind()`, a failing `unlink()` on a socket, herdr starting but never persisting state) before the workarounds were adopted, rather than assumed from documentation.

**Consequence:** the "use a named volume for anything that needs a socket or an atomic write, bind-mount only what genuinely needs to be a host path" rule in this project is specific to this host's platform. Moving to a platform without these limitations (Linux host, or a newer Docker Desktop backend) lifts several of the constraints recorded in the herdr state and mount entries — those entries' `Revisit when` conditions exist for exactly this.

**See:** herdr-state.md — 8df98718-04bf-4ac1-8b60-df6d70252503 — as of 2026-10-10
