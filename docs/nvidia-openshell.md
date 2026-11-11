# pi + herdr in NVIDIA OpenShell — research + hands-on spike, compared with sbx

as-of: 2026-11-11 · status: **spike run on pluto (OpenShell v0.1.8, MicroVM driver): T1–T6, T9 pass; gaps: hiding a file inside a *writable* repo; sandboxes restart when the gateway restarts** · NOT a decision

## Summary

- **It works, and pi + herdr fit better than our notes predicted.** herdr server ran as
  the sandbox's main process. Two pi panes ran in it, and pi answered via home-llm. After
  a full `sandbox stop`/`start`, herdr came back, restored its panes, and resumed pi with
  its conversation. Our notes said "one main process + one PTY, herdr expected to break".
  That was wrong.
- **The controls are finer-grained than sbx's.** Network rules are scoped per binary
  (only `node` may reach home-llm; `curl` gets denied on the same host:port). They can also
  be scoped per HTTP method/path, and they change live without a restart. Credentials are
  bound to binary + host + port + path. Every allowed or denied connection is logged with
  the binary and its process ancestry.
- **It runs with no account, no sudo, no systemd, and without the Docker engine.** On
  pluto it ran as plain user processes from `~/.local`, using the MicroVM driver
  (libkrun/KVM). It is Apache-2.0 and the gateway is self-hosted. Without KVM (e.g. a
  Hetzner Cloud VPS) the same policies run on the Docker or Podman driver, with a
  container wall instead of a VM wall.
- **Costs:** host directories reach a MicroVM only through ≤ 3 virtiofs mounts (on x86_64).
  NVIDIA warns that libkrun doesn't confine a compromised guest kernel to the mount source.
  Landlock has allow rules only, so a `.env` inside a writable repo stays readable. Our
  image needed PTY paths in the policy and a PATH fix. Releases come weekly (0.1.5 → 0.1.8
  in 3 weeks), so expect churn.

## Test results (pluto, 2026-11-11, OpenShell 0.1.8, `compute_driver = "vm"`)

Image: the existing sbx spike image `pi-herdr-sbx:spike` (pi 1.5.0, herdr 0.9.2, user
`agent` uid 1000), read from the local Docker image store. Policy:
`spike/openshell/policy-spike.yaml`. Probes: `spike/openshell/probe-inside.sh`.

| Test | Result | Evidence |
|---|---|---|
| T1 secrets out of sight | ✅ | The canary was stored as provider `canary` (`--from-existing`, so it never appeared in argv). Inside, `CANARY_KEY=openshell:resolve:env:v…_CANARY_KEY`. The host echo endpoint logged `real_canary_received=True`. A grep for the full canary pattern over `/proc/*/environ`, `/sandbox`, `/etc` and `/tmp` found nothing. `python3` sending the same placeholder to the same host got `EACCES`: the binary isn't in the profile. Host side, the canary isn't stored in plaintext in the gateway DB. A 32-byte `key-encryption-key.bin` (0600) sits next to it. |
| T2a pi → home-llm | ✅ | `pi -p --provider home-llm --model glm-5.3-flash-direct` printed `OPENSHELL-PI-OK` via `http://pluto:40115/v1`. The rule is `host: pluto, port: 40115, binaries: [/usr/bin/node]`. **`curl` to the same host:port is denied** (`binary '/usr/bin/curl' not allowed in policy 'home_llm'`). |
| T3 egress deny | ✅ | All denied, each with an OCSF log line: http and https to example.com, `https://1.1.1.1`, DNS-over-TCP to `8.8.8.8:53`, and `node` fetching example.com. DNS returns a **synthetic** `198.18.x.x` for every name. Names not in policy are logged `NET:REFUSE … policy_dns_ineligible`, with no `resolved=`, so they aren't resolved upstream. (The DNS exfil bug [#1169](https://github.com/NVIDIA/OpenShell/issues/1169) was fixed by this "policy DNS".) |
| T3 hot reload | ✅ | `policy update --add-endpoint example.com:443 --binary /usr/bin/curl --wait`: `000` → `200` → removed → `000`, with no restart. `policy list` shows revisions 1–3. |
| T4 host / LAN reach | ✅ | No docker socket. No SSH banner from `pluto:22` (`transparent TCP mapping does not authorize the requested port`) or from `host.openshell.internal:22`. Blocked: `192.168.1.1:80`, `169.254.169.254`, host `~/.pi` and `~/.ssh`. The VM has **no NIC** (only `lo` and `dummy0`). |
| T5 FS blast radius | ✅ | `/etc` and `/usr/local` are not writable. `/` and `/opt` aren't even listable: Landlock denies anything not in the policy. A virtiofs `read_only` mount isn't writable. Writes to `/sandbox` stay in the VM overlay. Inside the sandbox: `NoNewPrivs: 1`, `Seccomp: 2`, `CapEff: 0`. `sudo` refuses ("no new privileges"). The VM runs its own guest kernel (6.12.109). |
| T6 herdr as main process | ✅ | `sandbox create --detach -- herdr server`. Workspace, split, and **two pi panes** both worked. `agent prompt` reached a pane and got the reply `OPENSHELL-HERDR-PANE-OK`. Needs `/dev/ptmx`, `/dev/pts` and `/dev/tty` in `read_write`. Without them: `failed to openpty: Permission denied`. |
| T6 idle / detach / TUI | ✅ | With **no session for 150 s**, the sandbox stayed `Ready` and herdr + pi kept running (etime 04:14). There's no sbx-style auto-stop and no `-d` flag is needed. `openshell sandbox exec -n os-pi2 --tty -- herdr` drew the herdr TUI (workspace `os-spike`, pi pane content). Killing that client left the server running. |
| T6 gateway restart | ⚠️ | SIGTERM on the gateway **takes the VMs down with it**: the VM driver and supervisors are its children. After the gateway restarts, the sandbox comes back `Ready` with a fresh main process. herdr panes and pi resume, as after stop/start. So the gateway must run supervised: the packaged user systemd unit plus `loginctl enable-linger`. Our manual `setsid` start is spike-only. |
| T6 stop/start + resume | ✅ | `/sandbox` (home, `.pi`, herdr state) persists; `/tmp` does not. The main process `herdr server` is relaunched on `start`. With `pane_history = true` plus `herdr integration install pi`, panes come back and pi resumes its session. It answered `ZEBRA-4711`, a word planted before the stop. The first attempt failed with `pi: command not found`: `HOME=/sandbox`, and the login shell's PATH drops the image's npm-global bin. Fixed with one line in `/sandbox/.bashrc`. |
| T9 nested ro/rw | ✅ | Landlock `read_only: [/hostdev]` plus `read_write: [/hostdev/repoA]` makes repoA writable, and the write reaches the host. repoB and the `/hostdev` top level are read-only. |
| T9 hide a file | ⚠️ | **Inside a read-write repo: not possible.** Landlock has no deny rules, so `/hostdev/repoA/.env` stayed readable. **Inside a read-only tree it works by enumeration:** list siblings and files instead of the parent (`policy-t9-hide.yaml`). Result: `.env` denied, `README` readable, but `ls repoA` is denied too. The VM driver rejects single-file mounts, so sbx's empty-file shadow trick doesn't work. Fix: keep secrets out of mounted trees, or mount a clean copy. |
| UC2 git round trip | ✅ | no host mounts; custom profile (`auth_style: basic`, user `x-access-token`) lets only `/usr/bin/git` reach github.com:443, and only this repo's 3 git URL paths. Clone → commit → push OK (branch `openshell-uc2-test-20261111`). Inside only `GITHUB_TOKEN=openshell:resolve:env:v…` (hash ≠ real; 0 `github_pat_` hits). `git` to another repo → 403, `curl` anywhere → denied. Finer than sbx, which allows the whole host. NVIDIA's published GitHub profile uses bearer and blocks push, hence the custom one. Details: `spike/openshell/uc2-git-push.md` |
| UC2 on w4u | ✅ | same profile on w4u (Hyper-V guest, 2 GiB cap): push of `openshell-uc2-w4u-test-20261111` OK, placeholder only inside, 0 `github_pat_` hits, egress denied; create 4.3 s (cached image), ~+270 MiB RAM. Gateway stop on w4u needs the PID (process name differs from pluto). Details: `spike/openshell/uc2-w4u.md` |
| T2b keyed providers, T7 sandbox↔sandbox, T8 kit | ⏳ | not run. Docs show `openai`/`anthropic`/`github` example profiles. A VM has no NIC, so sandbox↔sandbox traffic can only go via the supervisor (untested). |

**Learned in practice:**
- `ls /` gives `Permission denied` by design. Anything a tool needs (`/opt`, `/var/lib`,
  `/dev/pts` …) must be in the policy. Keep `landlock.compatibility: hard_requirement`:
  the default `best_effort` **runs without filesystem rules** if Landlock fails.
- `sandbox upload <dir> <dest>` nests the directory (`/sandbox/.pi/.pi`). Upload to the
  parent instead. A single-file upload onto a missing path created a directory.
- `HOME=/sandbox` in the MicroVM, not the image's `/home/agent`. Login shells reset PATH.
  Put PATH, the pi config and the herdr config under `/sandbox`.
- Logs: `openshell logs <sbx>` gives OCSF lines with binary, ancestry and cmdline. This is
  better than `sbx policy log` for tuning rules. A denied binary even gets a "symlink hint"
  (`/usr/bin/python3` → `/usr/bin/python3.14`).
- Rules match the **resolved binary path** (`/proc/<pid>/exe`). Pin real paths, not symlinks.

## Corrections to earlier notes (`market-research-agentic-sandboxes.md`, `NOTES.md`)

- ❌ "Sandbox = one main process + one PTY; herdr multi-pane expected to break": **herdr +
  N pi panes run inside one sandbox** (T6). The single-stdin rule only applies to
  `sandbox connect` on the main process.
- ❌ "Docker driver needs the host Docker socket", read as "OpenShell needs Docker": the
  **MicroVM driver** (libkrun/KVM) needs neither Docker nor root. Podman rootless also exists.
- ❌ "No host bind-mount workflow": bind/virtiofs mounts exist, as an explicit unsafe opt-in
  (MicroVM: ≤ 3 dirs on x86_64).
- ⚠️ "Landlock per-path ro/rw": confirmed, but allow-list only. You can't hide a file
  inside a granted writable directory.
- ✅ Confirmed: seccomp, deny-by-default egress (hot-reloadable), host-side credential
  substitution toward approved endpoints, self-hosted gateway, macOS arm64 support (but
  see #4733).
- Version moved from v0.1.5 to **v0.1.8**. The licence is **Apache-2.0**.

## What it takes

| # | Need | Detail | Src |
|---|---|---|---|
| 1 | Host | Linux x86_64/arm64 (glibc ≥ 2.28 for the gateway) or macOS Apple silicon. Kernel with **Landlock ABI ≥ 3** (Linux ≥ 6.2). Windows: WSL2 experimental, native MXC in development. | L1 support-matrix |
| 2 | Compute driver | One per gateway. **Docker** (Engine ≥ 28, uses the host socket), **Podman** 5.x rootless, **MicroVM** (libkrun; KVM / Hypervisor.framework; opt-in, never auto-detected), Kubernetes. Auto-detect order: K8s → Podman → Docker. | L1 runtimes |
| 3 | Install (official) | `curl … install.sh \| sh`. On Ubuntu this runs `sudo apt-get install` of a .deb (CLI, gateway, prover, VM driver, *user* systemd unit), then `systemctl --user enable --now openshell-gateway`. postinst only runs `systemctl daemon-reload`. It doesn't touch Docker. | install.sh, .deb inspected |
| 3b | Install (what we did) | Extracted the same .deb (sha256-checked) to `~/.local/opt/openshell-0.1.8`. Ran `openshell-gateway` as a plain background process with `XDG_*` pointed at `~/.local/share/openshell-spike`. `spike/openshell/env.sh` and `gateway.toml.tmpl` reproduce it. No sudo, no systemd, no account. | spike |
| 4 | Gateway | Local mTLS gRPC on `127.0.0.1:17670`. SQLite state, credentials encrypted with a local key file. The CLI registers it via `openshell gateway add … --local`. | L1, spike |
| 5 | Image | Any Linux OCI image; for the VM driver, read from local Docker/Podman or a registry. The VM uses the image's `sandbox` account or uid 1000. **pi tutorial exists** ([run-pi-with-openrouter](https://docs.nvidia.com/openshell/v0.1.8/tutorials/run-pi-with-openrouter)). For herdr, add the PTY paths to the policy. | L1, spike |
| 6 | Host files | **Docker/Podman:** named volumes, tmpfs, or `bind` (opt-in, warned). **MicroVM:** virtiofs `bind` mounts, **max 3 on x86_64** (32 on arm64), directories only, no nesting. Opt-in: `allow_driver_config`, `enable_bind_mounts`, `resource_admission.enabled = false`. Alternatives: `--upload` / `sandbox download` (snapshot copy). | L1 runtimes |
| 7 | Credentials | Provider = profile (YAML: env var, header, endpoints, binaries) + `provider create --from-existing`. The workload sees `openshell:resolve:env:…`. The proxy substitutes it only if network policy **and** endpoint binding **and** placement (header/query/path) all pass; otherwise it fails closed (403 `credential_endpoint_mismatch`). It does **not** scrub responses. Custom OpenAI-compatible host: write your own profile. The `openai` profile is bound to the vendor host on purpose. | L1 providers, inference |
| 8 | Network | Deny all by default. Rules are `host` (exact or wildcard) + port + `binaries`; optional L7 (`rest` method/path, websocket, graphql, mcp, json-rpc); `allowed_ips`. Private IPs are blocked unless named by exact hostname or `allowed_ips`. Loopback/link-local are never allowed. A host service is reached via `host.openshell.internal:<port>` or a LAN hostname. Plain HTTP works (home-llm on `:40115`). TLS is terminated and inspected (the sandbox trusts a supervisor CA) unless `tls: skip`. | L1 network-rules, spike |

## Research answers (the six questions)

1. **Install / architecture / version / licence.** Its parts: CLI → gateway (control
   plane: state, policy, credentials; one per user/host) → compute driver → per-sandbox
   **supervisor**. The supervisor is the host-side proxy and DNS (in the VM driver it's a
   host process, `openshell-supervisor`). It talks to the in-sandbox `openshell-sandbox`
   launcher, which applies Landlock + seccomp and runs the workload. Docker is **not
   required**: MicroVM, Podman and K8s drivers exist. No k8s is needed locally. Current
   **v0.1.8 (2026-11-10)**, weekly stable releases. **Apache-2.0**, ~21k GitHub stars.
2. **Filesystem.** Landlock `read_only` / `read_write` path lists, fixed at creation, ≤ 256
   paths, allow rules only. "Most of ~/dev ro, one repo rw": ✅ (T9). "Hide a .env": ✅ only in
   a read-only tree by enumerating siblings; ❌ inside a writable dir.
3. **Network.** Deny by default, per binary, live-updatable, optional L7. LAN service:
   name it as an exact hostname (`pluto:40115`) or use `allowed_ips`. A gateway-host
   service: `host.openshell.internal`.
4. **Credentials.** Placeholder in env, substituted host-side. Bound to binary + endpoint
   + placement. Custom endpoint = custom profile (verified with the canary). GitHub: the
   `github` profile; L7 rules can allow fetch but deny `git-receive-pack`, or allow push to
   one repo only ([tutorial](https://docs.nvidia.com/openshell/v0.1.8/tutorials/github-push-access)).
5. **Process model.** One canonical main process (the `connect` target; one stdin owner,
   1 MiB replay) plus unlimited independent `exec --tty` shells. The main process can be a
   multiplexer: **herdr server + N pi panes works** (T6). Restart policy is gateway-owned
   (`never` / `on-failure` / `always`). Persistence: the sandbox record, policy, providers
   and `/sandbox` overlay survive stop/start; processes don't.
6. **Known limitations / issues.**
   - The libkrun virtiofs share isn't host-confined against a compromised guest kernel
     (docs warning; [#5437](https://github.com/NVIDIA/OpenShell/issues/5437) open).
   - macOS Docker Desktop VirtioFS bind mounts: Landlock denies reads
     ([#4733](https://github.com/NVIDIA/OpenShell/issues/4733) open, 2026-10-20). **Relevant
     for the Mac.**
   - Tools needing user namespaces (bubblewrap, Chromium's sandbox) fail
     ([#5370](https://github.com/NVIDIA/OpenShell/issues/5370),
     [#4098](https://github.com/NVIDIA/OpenShell/issues/4098)).
   - Fixed earlier: DNS exfil ([#1169](https://github.com/NVIDIA/OpenShell/issues/1169)),
     and PTY access needing policy changes ([#749](https://github.com/NVIDIA/OpenShell/issues/749)).
   - Credentials aren't scrubbed from responses (by design, docs).
   - NVIDIA's qualification profile "covers part of" the release policy.
   - No published GitHub security advisories (API returned 0, 2026-11-11).

## Pros

- **Finest-grained controls of anything we tested:** per-binary egress, L7 method/path
  rules, credential binding to binary + endpoint + header slot, hot-reloadable network
  policy with revisions, a policy prover, and OCSF audit logs with process ancestry.
- **Four walls stacked in the MicroVM driver:** VM (own kernel, no NIC) + Landlock +
  seccomp + no_new_privs/zero caps. The proxy and credentials live host-side.
- **herdr topology A works unchanged:** herdr server as main process, pi panes,
  resume across stop/start.
- **No vendor account, open source, self-hosted.** It runs fully user-local (no sudo) on
  pluto. Nothing leaves the machine.
- **Portability:** the MicroVM driver needs KVM, but the same policy model works on
  Docker/Podman (no KVM) and Kubernetes. A cheap VPS without nested virt still gets
  Landlock + seccomp + egress + credential brokering, behind a container wall.
- An official pi tutorial plus SDKs (Python, TS, Go, Rust).

## Cons / risks

- **No hiding of a file inside a writable tree** (Landlock allow rules only; no single-file
  VM mounts). sbx's empty-file shadow does this.
- **MicroVM host mounts:** max 3 on x86_64, directories only, no nesting. The opt-in
  disables resource admission, and NVIDIA warns a compromised guest kernel could reach
  other host files via libkrun (#5437). The safer path is upload/download snapshots, which
  is clunky for live editing.
- **Deny-by-default filesystem is strict:** images need tuning (`/dev/pts`, `/opt`, …), and
  each change means recreating the sandbox, since the filesystem policy is fixed at
  creation.
- **Young and fast-moving:** 0.1.x, weekly releases, an upgrade guide for breaking 0.1.0
  changes, ~645 open issues/PRs. The managed inference route was already removed in 0.1.5.
- **TLS interception** for inspected endpoints: the sandbox trusts a supervisor CA.
  Clients that pin certificates need `tls: skip`, which loses credential injection.
- The gateway holds a key file plus an encrypted DB under the user's home, readable by any
  `cgint` process (same class as sbx's 0700 file store).
- The official installer is system-level (`sudo apt`, user systemd). The user-local route
  we used is not documented as such (it works, see 3b).

## Head-to-head vs Docker Sandboxes (sbx)

| Dimension | OpenShell 0.1.8 (MicroVM driver) | sbx 0.51 |
|---|---|---|
| Isolation wall | libkrun microVM per sandbox (own kernel, **no NIC**) + Landlock + seccomp + NNP. Container wall on the Docker/Podman drivers. | microVM per sandbox; proxy in front |
| FS model | Landlock allow lists (ro/rw per path, nested rw-in-ro ✅); ≤ 3 virtiofs dir mounts (x86_64); no single-file masks → **can't hide `.env` in a rw repo** | `PATH[:ro]` workspaces, nested rw-in-ro ✅, single-file `:ro`, **empty-file shadow hides `.env`** ✅ |
| Egress | deny-all; **per binary** + host:port; L7 method/path; live reload with revisions; synthetic policy DNS | deny-all; per host:port per sandbox; live; DNS via policy resolver |
| Secrets | placeholder; bound to **binary + endpoint + header/query/path slot**; fail-closed; custom profiles in YAML | placeholder; header swap matched on host; `set-custom` experimental; OAuth kits (pi kit) |
| Audit | OCSF per connection with binary, ancestry and cmdline; `openshell logs` | `sbx policy log` (host, rule, count) |
| herdr fit | ✅ herdr server as main process; panes; TUI via `exec --tty`; resume after stop/start; no auto-stop; ⚠️ sandboxes restart when the gateway restarts | ✅ with `sbx run -d`; herdr started via exec; resume ✅ |
| Install footprint | 3 binaries (213 MB) in `~/.local/opt`, state in one dir; **no sudo, no account**; image cache ~4.4 GB | `apt install docker-sbx`, kvm group, **Docker login mandatory** |
| Portability | Linux x86/arm, macOS arm64; **VPS without KVM: Docker/Podman driver** (weaker wall, same policies); K8s | needs KVM (or Docker Cloud, paid); no non-VM fallback |
| Maturity | 0.1.x, weekly, Apache-2.0, ~21k stars | 0.5x, Docker-backed, closed CLI, free locally |

Bottom line (not a decision): sbx is simpler for "mount my repos, hide a .env". OpenShell
is stronger on egress/credential precision and auditability, and it needs no vendor
account and has a no-KVM fallback.

## Open questions

1. Live host mounts on the MicroVM driver (≤ 3, guest-kernel caveat) or upload/download
   snapshots? Or the Docker driver on pluto (needs the host Docker socket, which was
   off-limits on this production host)?
2. T2b: pi's codex/copilot OAuth through providers. Is there an OAuth refresh path for pi's
   `auth.json` like sbx's pi kit? Docs show refreshable providers (Microsoft Graph
   tutorial); not tested for pi.
3. Mac: does #4733 (Landlock vs Docker Desktop VirtioFS) block host repos on the Mac?
   Does the MicroVM driver on Hypervisor.framework avoid it?
4. Production shape on pluto: install the .deb plus user systemd and linger (sudo once),
   or keep the user-local tarball route under our own user unit? Sandboxes restart with
   the gateway (verified), so either way it must be supervised.
5. herdr web UI via `openshell forward` / `service expose`: untested.

## Spike artifacts and host footprint (pluto)

- Repo: `spike/openshell/` holds `env.sh`, `gateway.toml.tmpl`, `policy-spike.yaml`,
  `policy-t9-hide.yaml`, `profile-canary-echo.yaml`, `create-sandbox.sh`,
  `probe-inside.sh`, `t6-herdr-inside.sh`. T1 reuses `spike/sbx/echo-server.py`.
- Installed: `~/.local/opt/openshell-0.1.8/` (binaries) and
  `~/.local/share/openshell-spike/` (gateway config, TLS/JWT keys, SQLite DB, VM image
  cache, ~4.5 GB).
- State after the spike: all sandboxes and the canary provider are deleted. The gateway
  and echo server are stopped. Re-run: `. spike/openshell/env.sh; setsid nohup
  openshell-gateway >"$OS_ROOT/gateway.log" 2>&1 &`, then re-import the profile and create
  the provider, then `create-sandbox.sh`.
- Undo: delete those two directories (nothing is running). No
  packages, systemd units, Docker containers, networks or volumes were created. The VM
  driver only *read* `pi-herdr-sbx:spike` from the Docker image store. One throwaway
  `docker run --rm` of that image was used to inspect it.

## Sources (fetched 2026-11-11)

- L1 docs v0.1.8: [installation](https://docs.nvidia.com/openshell/v0.1.8/about/installation),
  [support matrix](https://docs.nvidia.com/openshell/v0.1.8/about/support-matrix),
  [architecture](https://docs.nvidia.com/openshell/v0.1.8/about/architecture),
  [sandboxes](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/sandboxes/overview),
  [runtimes](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/sandboxes/runtimes),
  [gateway config](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/gateways/configuration),
  [policies](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/policies/overview),
  [schema](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/policies/schema),
  [default policy](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/policies/default-policy),
  [network rules](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/policies/network-rules),
  [providers](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/providers/overview),
  [inference](https://docs.nvidia.com/openshell/v0.1.8/how-it-works/inference),
  [pi tutorial](https://docs.nvidia.com/openshell/v0.1.8/tutorials/run-pi-with-openrouter),
  [GitHub push tutorial](https://docs.nvidia.com/openshell/v0.1.8/tutorials/github-push-access).
- GitHub: [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) (licence, stars,
  releases via API), [install.sh](https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh),
  issues #749, #1169, #4098, #4733, #5370, #5437.
- Spike: local runs on pluto, 2026-11-11 (sandbox logs quoted above).
