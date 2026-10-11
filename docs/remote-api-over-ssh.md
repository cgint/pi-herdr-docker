# Remote API over SSH

Status: **WORKS TODAY, no code changes needed** (verified against current
`herdr-entrypoint.sh` + `herdr.sh`, 2026-10-10). This is the chosen path for
remotely driving herdr features, in particular the **agent control** surface
that the herdr-web bridge does not expose.

## The question this answers

"Remotely call herdr features" — the herdr-web bridge (v0.6.1, pinned in
`build-context/`) exposes a REST/WS API, but its `POST /api/command` is
whitelisted to workspace/tab/pane layout commands only. Its own test suite
asserts `agent.start` is **not** in the whitelist
(`bridge/src/web_bridge.rs`: `assert!(!ALLOWED_COMMANDS.contains(&"agent.start"))`).
The agent control surface — `agent start / prompt / list`, the part this
project exists for — is not reachable through the bridge API without forking
and rebuilding the bridge from patched source.

SSH reaches the **full herdr CLI** inside the container, so it covers the
gap with zero new code.

## What is already wired

| Piece | Where | State |
|---|---|---|
| `sshd` in container, pubkey-only | `herdr-entrypoint.sh` (`PermitRootLogin prohibit-password`, `PubkeyAuthentication yes`) | active |
| Host keys imported | `~/.ssh` mounted read-only at `/host-ssh`; entrypoint copies `id_*.pub` → container `authorized_keys` | active |
| Port publishing | `herdr.sh`: `-p ${PORT}:22`, base 2222, +1 per instance name (deterministic hash) | active |
| Multi-instance | `./herdr.sh -n alpha up` → own volume, own SSH port (2222 + hash%200) | active |

Any machine holding a private key whose public half is in `~/.ssh/` can
drive the container:

```
ssh -p 2222 root@127.0.0.1 "herdr agent prompt <pane> '...' --wait"
ssh -p 2222 root@127.0.0.1 "herdr agent list"
ssh -p 2222 root@127.0.0.1 "herdr workspace create --cwd /workspace/current-repo --label new"
ssh -p 2222 root@127.0.0.1 "herdr status"
```

Instance `alpha` uses port 2223+ (see `herdr.sh` PORT derivation); from a
remote host replace `127.0.0.1` with the Mac's reachable address.

## Caveats (read before relying on this)

1. **Port is not loopback-pinned.** `-p 2222:22` binds on all host
   interfaces, unlike the web port (`127.0.0.1:8787`, deliberately pinned).
   "Remote" therefore means *any reachable interface on the Mac* — LAN and
   Tailscale included. Fine for a trusted personal network; if the host
   ever sits on an untrusted LAN, pin the publish (`-p 127.0.0.1:2222:22`
   for host-only, or bind via Tailscale only).
2. **SSH access = root in the container.** The user-switch plan
   (`context/container-runtime.md`, `Status: open`) is not landed, so the
   login user is root, with `~/.pi` (including `auth.json` with cloud keys)
   read-writable and the repo mounted rw. Same threat model as the web UI
   ("web access = shell access"): the key *is* the credential.
3. **CLI semantics unchanged.** Remote runs obey the same herdr CLI rules
   as local ones — notably `herdr agent prompt … --wait` without `--until`
   for normal work (see `context/herdr-cli.md`).

## Why not the alternatives

| Option | Why not (for now) |
|---|---|
| Fork + rebuild the bridge with `agent.*` in `ALLOWED_COMMANDS` | Upstream drift, protocol 22 re-verification (herdr ↔ bridge pairing, see `herdr-web-ui-on-top.md`), a maintained fork. Real cost for a feature SSH already covers. |
| Thin API sidecar wrapping the herdr CLI/socket | Cleaner surface long-term (stable JSON, no shell-quoting, no root login), but it is new code to build and test — the right next step only if/when scripted automation outgrows `ssh host "herdr …"` ergonomics. |
| Web bridge API as-is | Sufficient for observation (`GET /api/snapshot`, `/ws/activity`) and layout control only; no agent commands (hard whitelist). |

**Revisit when:** the web bridge gains agent methods upstream; the
user-switch lands (SSH no longer gives root); or scripted remote control
needs more than one SSH call per operation (then evaluate the sidecar).

## Relationship to the web UI

Additive, not competing: `./herdr.sh up` (server + sshd, full CLI via SSH)
and `./herdr.sh up-web` (server + bridge, browser UI on 127.0.0.1:8787)
share the same herdr-state volume and remain mutually exclusive while
running (same reason as before: one state directory, one server). Pick the
surface per use case; state survives switching.
