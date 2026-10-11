# Herdr CLI

## herdr agent prompt: no --until for normal work

**Id:** 9691659f-06dd-4dc1-94cb-4dd8509c5bdf
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md` (herdr CLI section, from the project's own herdr skill file)
**Revisit when:** herdr's prompt --wait behavior changes

When driving herdr's agent-prompt command from the host and waiting for it to settle, do not add a `--until` flag for normal work; wait for the first settled idle/done/blocked state instead.

**Reason:** the wait command without `--until` accepts whichever of idle/done/blocked the agent settles into first, which is what pi does after a normal turn. Adding `--until done` (or similar) narrows the wait to one specific state; an agent that settles into idle — the normal end of a turn — is then reported as a timeout even though it finished fine.

**Rejected alternative:** use `--until done` so the wait is explicit about the expected end state. Produces false timeouts on the common path; `--until` is only for flows that genuinely need one specific state (e.g. waiting for blocked).
