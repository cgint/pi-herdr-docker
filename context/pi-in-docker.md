# Pi in Docker

## Pi package: @earendil-works/pi-coding-agent, not the frozen @mariozechner name

**Id:** 751c57b0-dc31-47a9-be9a-e31700df4f91
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** the pi package name changes again

The image installs pi from `@earendil-works/pi-coding-agent`.

**Reason:** the earlier name, `@mariozechner/pi-coding-agent`, was frozen at 0.73.1 and does not know newer model IDs. The active package line is `@earendil-works/pi-coding-agent` (0.87.1 at last build).

**Rejected alternative:** keep installing `@mariozechner/pi-coding-agent`. It still installs, but ships a stale, frozen version of the agent.

## Pi version pinned to @latest in the image

**Id:** c8964547-4e7d-48b5-97b9-d5622b930ebb
**Type:** workaround
**Status:** active
**Evidence:** inferred
**Source:** commit history, open items in `NOTES.md`
**Revisit when:** pi is pinned to an explicit version in `Dockerfile.herdr`

The Dockerfile installs pi from `@latest` instead of a pinned version.

**Reason:** deliberate open item, not an oversight: pinning a specific pi version (e.g. 0.87.1) so updates are deliberate is listed as follow-up work. Until then, every rebuild of the image picks up whatever the latest release is.

**Consequence:** image builds are not reproducible across time; a pi release can change agent behavior between builds without any change in this repository.

**Rejected alternative:** pin immediately. Deferred to the open-items list so the first herdr workflow could ship.
