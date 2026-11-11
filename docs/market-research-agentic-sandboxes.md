# Agentic sandboxes & remote execution environments — market research

**Date:** 2026-10-24 · **Buyer profile:** EU-based individual/small team, runs
coding agents (pi, Claude Code, Codex), needs **real data-protection guarantees
and/or self-hosting that keeps a real security boundary**.

**Why this document exists.** This repo (`pi-agent-docker`) is one answer to
"give a coding agent its own machine." It is not the only one, and the market
moved a lot underneath it. This is the decision basis: what exists, what each
option actually replaces, and which parts of it are verified.

**Evidence policy.** Every claim carries a tag:

| Tag | Meaning |
|---|---|
| `[L1]` | Read directly in a primary source (fetched this research pass, URL inline) |
| `[W]` | Prior-scout citation, or a well-known behaviour not re-fetched |
| `[U]` | Inference / reasoning, no page behind it |
| `[not published]` | The vendor publishes nothing on this — itself a market finding |

Working memos with full citations live in `agent/research/` (gitignored):
`M1` cloud sandbox APIs · `M2` remote dev environments · `M3` agent vendors'
own sandboxes · `M4` EU compliance · `M5` egress + macOS runtimes ·
`A1` OpenShell deep dive · `A3` alternatives sweep · `X1` Daytona-EU
adjudication · `X2` egress adjudication.

---

## 1. The map: two axes, not one

The phrase "agentic sandbox" hides two different products. Getting this wrong
is the single most common mistake in this space.

```
AXIS A — the agent runs INSIDE the sandbox          AXIS B — the agent runs ELSEWHERE
        (containment)                                        (remote control)

  ┌─────────────────────────┐                  ┌──────────────┐      ┌──────────────┐
  │  sandbox                │                  │   your       │      │   remote     │
  │  ┌───────────────────┐  │                  │   machine    │◄────►│   box        │
  │  │ agent + tools     │  │                  │              │      │              │
  │  │ can only touch    │  │                  │  agent brain │      │  repo, tools │
  │  │ what the box has  │  │                  │  (local)     │      │  shell, tests│
  │  └───────────────────┘  │                  └──────────────┘      └──────────────┘
  └─────────────────────────┘                     network path (SSH / API / sync)
   Docker, OpenShell, gVisor,
   Firecracker, sbx, Apple VM          ← code stays yours      code goes there →   E2B,
                                                               Daytona, Modal,
                                                               Codespaces, Copilot
                                                               coding agent, Claude
                                                               Code on the web
```

**Why the distinction decides everything for an EU buyer.** On axis A with a
local runtime, *nothing leaves your machine* — the sandbox is jurisdiction-
neutral. On axis B, your source code, prompts and test output physically land
on someone else's infrastructure, which drags in CRA/CLOUD Act exposure no
matter what the vendor's EU region says `[U]`.

This repo lives on **axis A, local**. That is its strongest and least-appreciated
property.

---

## 2. Verdicts up front

1. **This repo is not obsolete — but it is thinner than it looks.** It occupies
   a real niche (persistent, multi-pane, attachable, local, EU-neutral) that
   none of the cloud options serve. Its *security* posture, however, is the
   weakest of any local option surveyed `[L1][W]`.
2. **NVIDIA OpenShell does not replace it.** OpenShell is a policy-and-network
   sandbox runtime; its sandbox is an agent-*process*-lifetime object with one
   main process and one PTY. This repo's whole purpose — many panes you
   detach/reattach to over days — is the exact inverse. The honest integration
   is OpenShell as the *compute driver underneath*, herdr as the orchestrator
   outside `[L1]`.
3. **Apple `container` is the genuinely-new item everyone missed**, and it is
   directly on target: one lightweight VM **per container** (not one shared VM
   for all), sub-second boot, unix sockets and bind mounts that *work* — the
   exact wall that forced this repo onto a named volume `[L1]`.
4. **The EU filter eliminates most of the market.** Of the managed agent-
   sandbox vendors, one has a verified self-serve EU region (Daytona), one is
   open-source self-hostable (Coder), one has an Apache-2.0 self-host escape
   hatch (E2B Embed), and the rest are US-entity managed services with no
   self-host `[L1]`.
5. **An EU-owned *agent-sandbox product* does not exist in 2026.** EU hosts
   (Hetzner, OVHcloud, Scaleway, Exoscale, STACKIT, UpCloud, IONOS) sell VPS and
   bare metal; you compose the sandbox layer yourself. That gap is real `[L1][W]`.
6. **No agent isolates by default except one.** Of 12 coding agents surveyed,
   4 ship a sandbox mechanism and **only Codex CLI turns it on at launch**;
   Claude Code, Copilot CLI and Zed build a real OS sandbox and ship it **off**
   `[L1][W]`. "Has a sandbox" and "is sandboxed" are different claims.
7. **The three gaps Docker does not fill** are egress allowlisting, credential
   brokering, and protected-path read-only sub-mounts. Everything else the
   vendors build (filesystem policy, syscall filtering) is something a container
   boundary already gives you more cheaply `[W]`.
8. **Egress control on macOS Docker Desktop is real but partial** — squid
   sidecar on an `--internal` network + `NODE_USE_ENV_PROXY=1` + git
   `insteadOf`. It gates *traffic*, not *intent* `[L1][W]`.

---

## 3. Axis A — running an agent inside a sandbox (local)

### 3.1 What each option actually gives you

| Option | Isolation unit | Filesystem control | Egress control | Agent sees a real key? | EU / self-host | Verdict |
|---|---|---|---|---|---|---|
| **Plain Docker (this repo)** | container, 1 shared Linux VM on macOS | mounts only: whole-dir ro/rw, no per-path deny | none — full egress by design | **yes** (env + rw `~/.pi`) `[L1]` | local, neutral, no third party | **keep, harden** |
| **Apple `container`** | **one lightweight VM per container** (Apple Virtualization.framework, Kata kernel, sub-second boot) `[L1]` | `--volume` bind mounts; **`--ssh` bridges `SSH_AUTH_SOCK` into the guest** | none built in | yes (your env) | Apple OSS Apache-2.0, on your Mac, **no processor at all** `[L1]` | **experiment — highest value** |
| **`container machine`** | same VM, but `$HOME` rw at same path, `--cap-add ALL`, `--masked-path NONE`, passwordless sudo — Apple's own WARNING says it "trades away much of the isolation" `[L1]` | full home | none | yes | same | **reject** — this is the anti-pattern |
| **NVIDIA OpenShell** | sandbox = one main process + supervisor; Landlock ABI3+, seccomp user-notification, `/proc` executable identity `[L1]` | **per-path Landlock read vs read+write, locked at creation** `[L1]` | **deny-by-default, DNS+TCP mediated, hot-reloadable** `[L1]` | **no — supervisor injects it only toward approved endpoints** `[L1]` | NVIDIA OSS; macOS arm64 + Docker Desktop officially Supported; **self-host gateway** `[L1]` | **complement, not replace** |
| **Docker Sandboxes (`sbx`)** | microVM per agent, in-sandbox credential mgmt, MCP gateway `[L1]` | — | managed by Docker | no — proxy substitutes placeholder | **free for local use incl. commercial; Docker account login required** (corrected 2026-11-11, see `docs/docker-sandbox-sbx.md`) | **upgrade path if threat escalates** |
| **Gondolin extension** | local QEMU micro-VM (HVF on Apple Silicon), *tools only* — the pi process stays on the host `[SRC]` | **programmable VFS**: readonly + shadow providers, per-path deny, symlink-escape blocking `[SRC]` | **mediated by design** — no generic NAT, host terminates/classifies all TCP (HTTP/TLS/SSH only, unknown blocked), internal ranges blocked by default, synthetic DNS + rebinding protection `[SRC]` | **no — host-side placeholder substitution, per-secret host allowlist** `[SRC]` | local, pi's own org; macOS-native via HVF | **complement** — the egress+secrets control Docker can't express; not a herdr replacement |
| **gVisor / Kata / Firecracker** | user-space or hypervisor kernel; real isolation tier | as configured | as configured | as configured | self-host anywhere | **not worth it on macOS** — Docker Desktop already gives a VM wall; adds build pain `[W]` |

### 3.2 The one thing to notice about the table

Four of these seven give you *no credential boundary at all*. That is not a
footnote — it is the dominant threat. In this repo today an agent can read the
LLM key from `~/.pi` **and** reach the open internet, which is the full
"private data + untrusted input + exfiltration path" trifecta `[W]`.

OpenShell is the only surveyed option that breaks that structurally rather
than by mount discipline: the key never exists inside the sandbox. Docker cannot
express this — it has no notion of brokering a credential `[L1]`.

### 3.3 Maturity reality on the two headline options

- **OpenShell:** v0.1.5, weekly stable target, backward-compatible across
  patch releases, breaking changes require a minor bump, N-1 maintenance `[L1]`.
  NVIDIA's own support matrix says the qualification profile "covers **part of**
  the complete release qualification policy" `[L1]`. Real contract, young
  product; risk is operational churn, not silent breakage.
- **Apple `container`:** mature enough to run daily (v1.6.1 → Oct 2026) but
  **macOS 26 + Apple silicon only**, no `docker compose`, no `docker exec` `[L1]`.
  Adopting it means rewriting the repo's CLI layer, not changing a config — that
  is the real cost of the experiment.

---

## 4. Axis B — remote environments the agent operates

### 4.1 The market, filtered for an EU individual

| Player | What it is | Isolation | Long-lived + attachable | Local-repo sync | Self-host | EU region | Solo-dev DPA | EU verdict |
|---|---|---|---|---|---|---|---|---|
| **Daytona** | sandbox API, cloud-first | containers (runc) default; **Firecracker microVM tier** | **yes** — `autoStopInterval=0`, `daytona ssh` `[L1]` | **yes, first-class** — bidirectional `sandbox sync --watch` `[L1]` | enterprise/BYOC only `[W]` | **yes — `eu` shared region, "available to all organizations"** `[L1]` (adjudicated, see X1) | **not published** `[L1]` | **allow** (only caveat: no published DPA) |
| **Coder** | self-hosted dev-env platform | container or full VM per workspace | **yes** — `coder ssh`, auto-sleep/wake `[L1][W]` | n/a (your own infra) | **yes — AGPL-3.0, Docker/K8s/air-gapped** `[L1]` | n/a — deploy anywhere | n/a — you are the controller | **allow (strongest sovereignty)** |
| **E2B** | reference sandbox API | Firecracker microVM, ~150 ms cold start, snapshot incl. **memory** `[L1]` | paused kept indefinitely | SDK upload/download only | **E2B Embed, Apache-2.0** (one Linux host with KVM) `[L1]` | managed cloud = GCP, **no EU region** `[L1]` | by email, no sales gate `[L1]` | **conditional** — US entity; self-host is the escape |
| **Fly.io Machines** | microVM substrate (+ "Sprites" persistent agent VMs) | Firecracker, 300–800 ms suspend-resume | **no hard cap** — run indefinitely `[L1][W]` | DIY (SSH/git) | no | **yes — `ams`, Frankfurt** `[L1]` | not surfaced | **conditional** |
| **Modal** | serverless + sandboxes | gVisor default, full microVM tier | max 24 h `[L1]` | SDK only | **no** | not surfaced | not surfaced | **fail on 24 h cap + no self-host** |
| **Vercel Sandbox / Cloudflare Sandboxes** | agent runtimes | not retrieved | ephemeral | no | **no** `[L1]` | edge only, no dedicated region | not surfaced `[U]` | **conditional** |
| **Hyperscalers (AWS AgentCore, Azure CAA Sessions, GCP Cloud Run)** | agent platforms | gVisor/container/microVM | function-shaped, **not attachable** `[L1][W]` | no | no | **yes, named regions + public DPA/subprocessor list** `[W][U]` | yes — standard self-serve DPA | **conditional** — best paperwork, worst fit for interactive work |
| **Gitpod / Ona** | pivoted to autonomous-agent service | "OS-level" (unspecified) | ephemeral by design | no | no | unverified | — | **fail — new signup closed** `[L1]` |
| **CodeSandbox / Northflank** | devboxes / PaaS | docs 403 `[not retrieved]` | — | — | no | US / **UK (not EU)** `[L1]` | — | **fail / conditional** |

**Graveyard, because a market memo that only lists survivors is a sales sheet:**
Gitpod → Ona (signup closed), DevPod (domain now redirects to a personal GitHub
profile), Runloop (winding down), Blaxel (absorbed into Baseten), Portkey OSS
(frozen, rebranded to Prisma AIRS), OpenVSCode Server (DNS no longer resolves)
`[L1][W]`. Two of those were the obvious "just self-host this" answer two years
ago.

### 4.2 The honest read on axis B

**No player passes all three filters at once** — EU data-protection *and*
self-hostable *and* "drive a remote box over my real repo" `[L1]`.

```
                  EU / DPA solid        self-hostable        local-repo sync
hyperscalers ──────────●
Coder ──────────────────────────────────●
E2B Embed ──────────────────────────────●         (no local sync)
Daytona ────────●───────────────────────●───────────────●   ← one EU region only
Fly.io ─────────●────────────────────────────────────────
```

So a solo EU developer must relax one filter. **Relaxing "managed" is cheapest**:
self-host on EU infrastructure and the DPA question disappears, because there is
no processor. That is Coder, or the minimal pattern below.

### 4.3 The minimal pattern nobody should dismiss

```
EU VPS (Hetzner/OVH/Scaleway/Exoscale, €3–15/mo)
  └── Docker or E2B Embed
        └── per-agent container / microVM
              └── tmux or zellij  ← multi-pane, detach/reattach, survives disconnects
                    └── pi / Claude Code
connect: mosh (resilient over wifi) or SSH
```

Every platform in §4.1 is this pattern with identity, networking and lifecycle
bolted on `[U]`. The pattern is a day of work, costs pocket money, keeps all
data in the EU, and has no vendor risk. What you give up: snapshots, a control
plane, audit, and someone else owning patching. **Self-hosted is not
automatically secure** — you inherit egress policy, secret hygiene and
isolation, which is precisely §5.

---

## 5. The gaps that actually matter (and what closes them)

Only three things separate this repo from a decent posture. Everything else
is decoration.

| Gap | Why Docker can't close it | What closes it | Cost | EU impact |
|---|---|---|---|---|
| **Credential brokering** — the agent holds the LLM key | Docker has no broker concept | **LiteLLM Proxy sidecar** (agent gets a placeholder); **Infisical Agent Vault** for npm/git/registry creds | low — ~20 min for LiteLLM `[L1]` | key stays in *your* proxy; no processor |
| **Egress allowlisting** | Docker Desktop has no per-container domain policy | **squid sidecar on an `--internal` network, no TLS interception** | medium — see config below `[L1][W]` | self-hosted, no third party |
| **Protected-path read-only inside a writable root** | mounts are whole-directory | per-path Landlock (OpenShell) or narrower mount set | low (mounts) to high (OpenShell) | — |

### 5.1 Egress: real, but only with two opt-ins

The design was adjudicated between two conflicting memos (`X2`). Verdict:

- **squid is right, not LittleProxy, not mitmproxy.** Domain-gated `CONNECT`
  needs no TLS interception, so no CA, no MITM `[L1]`. mitmproxy's only added
  value is body inspection, which an allowlist doesn't need.
- **`--internal` genuinely removes the route** — IP literals and public DNS
  become unreachable, so the proxy is *mandatory*, not advisory `[W]`.
- **The catch is the agent itself.** Node does **not** honour `HTTPS_PROXY`
  natively — without `NODE_USE_ENV_PROXY=1`, pi's own `fetch()` bypasses the
  proxy entirely and the whole control is theatre `[U]`. Same for git-over-SSH
  unless rewritten with `insteadOf`.

Minimal `squid.conf`, no MITM:

```squid
http_port 3128
acl CONNECT method CONNECT
acl SSL_ports port 443
acl allowed_dstdomain dstdomain .github.com .npmjs.org .nodejs.org \
    registry.npmjs.org pypi.org files.pythonhosted.org
http_access allow CONNECT allowed_dstdomain SSL_ports
http_access allow allowed_dstdomain
http_access deny all
access_log /var/log/squid/access.log squid
```

Required opt-ins or it is not a boundary: agent env `HTTPS_PROXY`, `HTTP_PROXY`,
**`NODE_USE_ENV_PROXY=1`**; git `url."https://github.com/".insteadOf
"ssh://git@github.com/"`; agent container on `internal: true` network.

**What it stops:** exfiltration to an unlisted host over proxy-honouring
HTTP(S); every attempt is logged. **What it does not stop:** abuse of an
allowlisted host, DNS tunnelling through the allowed resolver, or a secret
smuggled inside a legitimate API call. It gates traffic, not intent `[L1][W]`.

---

## 6. What the vendor landscape implies about this repo

Of 12 coding agents surveyed `[M3]`:

- **4 ship a sandbox mechanism; 1 enforces it by default** (Codex CLI — Seatbelt
  on macOS, bubblewrap on Linux, network off). Claude Code, Copilot CLI and Zed
  build one and ship it **off**. Aider, Continue, Warp, Gemini CLI run with
  nothing.
- **The local-sandbox convergence is real and OS-level, independent of
  containers** — Seatbelt (macOS) and bubblewrap (Linux). Landlock is *not* the
  shipped mechanism in either, despite marketing `[L1]`.
- **Remote execution is a separate product from sandboxing.** Six vendors move
  your code to their infra (Claude Code on the web, Codex cloud, Jules, Cursor
  Cloud, Copilot coding agent on GitHub Actions, Devin). **None documents an EU
  region, and none offers self-host for solo developers** `[not published]`.
- **Implication for a home-grown container setup:** the filesystem/syscall
  primitives these vendors build are unnecessary here — a container boundary is
  already harder than a user-space sandbox. The three gaps in §5 are the ones
  that matter, and the vendors close them with a proxy and a credential
  service, not with better mount hygiene `[W]`.

---

## 7. Recommendation

Sequenced by value per unit of effort. Nothing here is a rewrite.

**Do now (hours, no architecture change):**
1. **LiteLLM Proxy sidecar.** The single highest-value move in the whole
   survey: the agent stops holding the LLM key. ~20 minutes.
2. **Shrink mounts.** `~/.ssh` → not mounted (or only `known_hosts`); `~/.pi`
   → read-only or a narrowed subset; repo mounts already `:ro` except the
   working copy. Cheap, honest, and removes the biggest leak `[W]`.
3. **Stop publishing SSH on all interfaces.** `-p "${PORT}:22"` currently binds
   0.0.0.0; bind to `127.0.0.1`.

**Do next (a day, closes a real gap):**
4. **squid egress sidecar** per §5.1, *with* `NODE_USE_ENV_PROXY=1` and the git
   `insteadOf` rewrite. Without those two, don't bother — it would be security
   theatre.
5. **Non-root container** + `--cap-drop ALL`, `--no-new-privileges`, pids/memory
   limits. Docker can express all of this; the repo just doesn't.

**Experiment (real decision, real cost):**
6. **Apple `container`, one herdr agent in a per-container VM.** If it works
   daily, the entire named-volume + macOS-filesystem-workaround stack becomes
   unnecessary, because unix sockets and bind mounts work natively. Cost: CLI
   rewrite, macOS 26 only.
7. **OpenShell as a compute driver underneath herdr** — not as a replacement.
   Take it when you want credential brokering and kernel-enforced paths without
   trusting your own mount discipline.

**Adopt only if the threat escalates:**
8. **Docker Sandboxes (`sbx`)** — right product (microVM per agent), wrong
   default: needs a Docker account login (local use is free; corrected 2026-11-11).

**Explicitly rejected:** `container machine` (Apple's own WARNING: trades away the isolation);
gVisor/Kata/Nix on macOS (cost without benefit — Docker Desktop already provides
a VM wall); every US-entity managed sandbox without self-host, for an EU buyer.

---

## 8. Open questions / what this research does not establish

- **Daytona's DPA and subprocessor list are not published** `[L1]`. The `eu`
  region is confirmed self-serve, but a signed DPA without enterprise sales is
  unproven. If that matters, Daytona is out and Coder/self-host is in.
- **E2B Embed self-host on an EU VPS is untested here.** It is Apache-2.0 and
  documented as "one Linux host with KVM" — but nobody in this research ran it.
- **Apple `container` + herdr is untested.** This is the one experiment that
  could invalidate the repo's named-volume design; it should be run before any
  larger refactor.
- **OpenShell on macOS: the host wall is still Docker Desktop's VM** `[U]`.
  OpenShell fixes the agent-reach half (Landlock, egress, credentials); it does
  not make the macOS hypervisor boundary stronger.
- **`herdr` multi-pane inside OpenShell is untested and expected to break** —
  OpenShell is one main process, one PTY, one stdin owner `[L1]`; that is
  incompatible with N concurrent panes by construction.
- **No EU-owned agent-sandbox product exists in 2026** `[L1][W]`. That is a
  finding, not a gap in the research — and it is the most likely thing to
  change within a year.
