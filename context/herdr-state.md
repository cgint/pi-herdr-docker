# Herdr state

## Herdr state on a named volume, not a bind mount

**Id:** 8df98718-04bf-4ac1-8b60-df6d70252503
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`; rejected-approaches section there
**Revisit when:** macOS Docker Desktop's gRPC-Fuse limitations change

Herdr's state directory is a Docker named volume, not a bind mount from the host.

**Reason:** macOS Docker Desktop's gRPC-Fuse implementation cannot create unix domain sockets on bind mounts — `bind()` fails and the socket file cannot be removed — and herdr's server requires a socket in its state directory. A bind-mounted state directory therefore cannot work at all, not just partially.

**Rejected alternative:** bind-mount the herdr state directory from the host. Verified to fail: sockets cannot be created, and stale ones cannot be cleaned up from inside the container (socket removal returns an unsupported error on the host path).

**Rejected alternative:** bind-mount individual state files (session file, history file) from the host. Herdr persists state with an atomic rename pattern; rename-over-existing-file fails silently on macOS bind mounts. Herdr would start but never persist anything.

**Rejected alternative:** a per-project host directory mounted in, instead of one state directory. Same socket and rename failure as the first two; the named volume is the only persistence that works on this host.

## Herdr state directory follows $HOME/.config/herdr; HERDR_CONFIG_DIR is not honored

**Id:** ab667af7-716b-4532-85ee-2660d4e13f91
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md` (herdr 0.9.1)
**Revisit when:** a herdr release honors HERDR_CONFIG_DIR

The container sets `HOME` and mounts the state volume at `$HOME/.config/herdr`, rather than setting `HERDR_CONFIG_DIR` to point herdr at the volume.

**Reason:** herdr 0.9.1 ignores `HERDR_CONFIG_DIR` entirely and always uses `$HOME/.config/herdr`; changing `HOME` moves the state directory, and that is honored. The mount therefore has to land exactly where herdr looks, via `HOME`.

**Rejected alternative:** set `HERDR_CONFIG_DIR` to the volume path and leave `HOME` at the default. Verified ineffective on 0.9.1; the state directory would silently resolve elsewhere.

## Herdr config self-contained in the repo, not symlinked to the host config

**Id:** 15dd3e33-1f72-4887-adf8-f982c33565f0
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commit 8741c46, user requirements in `NOTES.md`
**Revisit when:** the repo stops being intended as a self-contained recipe

`herdr-config.toml` lives in this repository and is copied into the container's state directory on first start.

**Reason:** the repository is meant to be a self-contained recipe — everything needed to reproduce the setup is in the repo, not linked to host-specific locations like a user's own herdr config directory.

**Rejected alternative:** link or mount the user's existing host herdr config into the container. It breaks the self-contained property and leaks host-specific settings into a throwaway container.

## herdr.sh down (SIGTERM) is the shutdown path, not the herdr API

**Id:** 6351bb41-1742-4cbb-b011-11bf1a48edfa
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** herdr's shutdown behavior changes

Stopping the container goes through `docker rm -f` (SIGTERM) or compose down, which lets herdr clean up its socket files before exiting.

**Reason:** herdr's server-stop command exits the server process immediately; when herdr is the container's main process the container dies without cleaning up its sockets, and a stale socket in the (named-volume) state directory then blocks the next start until it is manually deleted.

**Rejected alternative:** send the herdr server-stop API command from the host and let the container die. Leaves stale sockets behind; the clean socket cleanup only happens on SIGTERM.

## session-history.json can contain secrets

**Id:** 69ca4aeb-d4d5-479b-b386-b9cc6a525240
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** open items in `NOTES.md`
**Revisit when:** pane_history is turned off, or herdr stops writing terminal output to history

Herdr's pane-history file records terminal output, which can include API keys or passwords an agent prints during a session.

**Reason:** `pane_history = true` in the container's herdr config makes herdr persist what appears in agent panes; that is by design (re-attach after a crash and see what happened), but it means sensitive output ends up in the state volume.

**Consequence:** the state volume holds anything an agent ever printed. The volume is not directly readable from the macOS host (it lives inside the Docker VM), which is a mitigation but not a guarantee — `docker cp` or a volume dump would expose it.

**Considered:** setting `pane_history = false` in the container config was recorded as an open item. Trade-off: lose the ability to see what a pane did before a crash, in exchange for not accumulating printed secrets.
