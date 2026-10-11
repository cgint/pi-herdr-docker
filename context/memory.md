# Memory

## Durable pairing memory is filesystem-persisted, in canonical per-type homes

**Id:** 3ec796ca-7a5c-426f-aef2-a685d825bee1
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** AGENTS.md durable pairing memory section, commit 8741c46
**Revisit when:** the memory scheme is replaced

The project's durable pairing memory (decisions, verified findings, rejected approaches, open items) lives in committed Markdown files by type — purpose and pointers in `AGENTS.md`, user-facing workflow docs in `README.md`, verified technical findings and rejected approaches in `NOTES.md`, planned architectures in `docs/` — rather than in agent session history.

**Reason:** agent session memory does not survive across sessions, agents, or machines; a project that future agents (human or AI) will work on needs its reasoning in files that are versioned, searchable, and shared with the code. The selection test in `AGENTS.md` (future usefulness, consequence, essence, home) is the bar for what gets persisted where.

**Rejected alternative:** rely on agent session transcripts or a shared "memory" service for the project's rationale. A transcript is per-session and per-agent; a service adds a dependency the project's "self-contained, no daemon" design explicitly avoids (see the herdr state entries, which apply the same reasoning to runtime state).

**Consequence:** an agent that does work in this project and finds durable, future-useful information is expected to write it into the matching file as part of finishing the work, not at the end of the session.
