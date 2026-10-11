# Container runtime

## Base image: node:22-trixie

**Id:** 9e25f3ae-5974-4dcb-a65c-ce41d5f13d8d
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** pi supports Node 20 again, or Debian trixie leaves Debian stable

Both Dockerfiles use `node:22-trixie` as the base image.

**Reason:** pi >= 0.84 requires Node >= 22 — it uses `fs.globSync`, which does not exist on Node 20. Trixie is Debian stable.

**Rejected alternative:** Node 20 base image. It works until pi is invoked, then crashes; pi >= 0.84 cannot run on it at all.

**Rejected alternative:** older Debian (bookworm/bullseye). Not wrong, but trixie is what the node:22 image ships by default and nothing here needs an older userland.

## Container runs as root; named-user switch is planned but not implemented

**Id:** 70d5ccfa-fcdd-4d37-9185-0336e6730434
**Type:** decision
**Status:** open
**Evidence:** inferred
**Source:** commit 88d8d66, user switch plan in `NOTES.md`
**Revisit when:** the user switch plan lands, or the plan is abandoned

The container runs as root (UID 0, GID 0). A documented plan exists to run it as a named user matching the host UID/GID so files written into mounted directories are owned correctly, but it has not been implemented.

**Reason (for the plan, confirmed):** files pi writes into bind-mounted host directories must carry the host user's UID/GID or the host user cannot manage them later. Host facts used by the plan: the host user's UID maps directly to the same container UID on macOS Docker Desktop (verified 2026-09-29); in Debian trixie GID 20 is already the existing `dialout` group, so no groupadd is needed; pi's profile directory contains relative symlinks that break if the profile is mounted at anything other than a flat path under the home directory. (The concrete UID/GID pair is recorded in `NOTES.md`, the maintainer's working notes.)

**Reason (for still being root):** unknown — no record of why the switch has not been done since the plan was written (2026-09-29).

**Considered:** the original plan (sshd as root + privilege transition in the entrypoint + marker-file ownership fix) was reviewed by three sub-agent reviewers and judged sound but over-engineered. The revised design: create the user in the Dockerfile, pass the UID/GID to `docker run`, drop all in-entrypoint privilege logic, do a one-time volume ownership migration manually, and accept that a stale working directory recorded in herdr's session state survives the switch (the user creates a new workspace). Rollback is a `docker rm -f`, a one-time ownership migration back to root, and reverting the script change.

**Why this needs an answer:** until the switch lands, everything pi writes into mounted directories is root-owned on the host, which is the exact problem the plan exists to fix; an open question about why it is still open is recorded rather than guessed (Core rule 1).
