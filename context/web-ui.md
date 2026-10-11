# Web UI

## Web bridge is additive over the server image; same herdr-state volume

**Id:** 74a925be-5622-4c10-99a2-3d7ffdf26a70
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commit 8a3385f, herdr-web design doc in docs/
**Revisit when:** the web bridge is removed, or herdr-web gains its own state

The web-UI bridge is built on top of the herdr server image (a second Dockerfile that adds the web component to the same base) and drives the same herdr-state named volume as the plain server container, rather than running a separate herdr instance with its own state.

**Reason:** the browser UI is a second surface over one herdr session, not a second session — attaching from a terminal and from a browser should show the same panes and agents. Building the web image on top of the server image (rather than a parallel image) keeps the two from drifting apart, and reusing the state volume means switching between the two workflows does not lose the working state.

**Rejected alternative:** a separate web container with its own herdr instance and state volume. Two independent herdr sessions for one logical workspace; the user would have to recreate panes/agents in the second one.

**Consequence:** the two workflows (plain server container, web bridge container) are mutually exclusive while running — they share the same state volume, so the web workflow checks that the plain container is not running before starting (and vice versa).
