# Mounts

## ~/dev and ~/dev-external mounted read-only, with explicit read-write overrides

**Id:** d2e406bd-4988-4e2d-b7af-56a42ef584c2
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commits 1caf92d, b53a31c; user requirements in `NOTES.md`
**Revisit when:** the default mount policy changes

The herdr container mounts `~/dev` and `~/dev-external` read-only, at the host's own paths inside the container; specific subdirectories can be overridden read-write via an environment variable listing them.

**Reason:** the default-deny policy — the agent sees the whole development tree but cannot write to it unless a specific directory is explicitly opted in — is a stated user requirement. Mounting at the host's own paths (rather than a translated container path) means no path-translation logic in the script: the same path works on both sides.

**Rejected alternative:** mount the development directories read-write by default. The agent could corrupt or rewrite any of the host's other projects while working in one.

**Rejected alternative:** translate host paths to different container paths. Requires the agent and any tooling to know the mapping; keeping the identical path on both sides removes that class of bug.

## The working repository is the only writable mount by default

**Id:** eb30c1b5-d5cd-41f7-9afb-c605039d4438
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commits 8741c46, b53a31c; user requirements in `NOTES.md`
**Revisit when:** the default mount policy changes

The repository the container works in is mounted read-write (at a well-known in-container path) and is the only writable project-content mount by default; everything else is read-only unless explicitly overridden.

**Reason:** same rationale as the read-only default — an agent working on one repository should not be able to touch the rest of the host's development tree without an explicit, per-invocation opt-in. The opt-in mechanism is the read-write override variable from the read-only-defaults entry.

**See:** mounts.md — d2e406bd-4988-4e2d-b7af-56a42ef584c2 — as of 2026-10-10
