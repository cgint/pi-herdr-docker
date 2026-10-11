# Entrypoint

## Entrypoint removes stale herdr sockets before starting the server

**Id:** 26072ca3-ec98-4a53-ae01-b8da9723cbd6
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commit 97c7048
**Revisit when:** herdr stops using a fixed socket path, or the state directory moves

The entrypoint deletes any socket files left in the herdr state directory before starting the herdr server.

**Reason:** if the container was killed or crashed without a clean shutdown (SIGTERM path), herdr's socket files can remain in the (named-volume) state directory, and the next server start fails because the socket path is already taken. Removing them at start makes a crash-then-restart cycle work without manual intervention.

**Rejected alternative:** require a clean `herdr.sh down` before every restart. The whole point of the named volume is that state survives container death; a socket-cleanup requirement would turn every crash into a manual-recovery step.

**Note:** this complements, not replaces, the clean-shutdown recommendation in the herdr state entries — clean shutdown still avoids the stale-socket condition; this makes the messy path survivable.

**See:** herdr-state.md — 6351bb41-1742-4cbb-b011-11bf1a48edfa — as of 2026-10-10
