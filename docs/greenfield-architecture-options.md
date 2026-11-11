# Greenfield stack options — design reasoning, not a decision

Date: 2026-10-24. Status: **open design discussion.**

## What this document is

Reasoning about what the pi+herdr stack would look like **if nothing existed yet** —
i.e. if the Docker recipes in this repo were not a given. It records:

- the question and its framing,
- the premises it rests on, each labelled by evidential status,
- three candidate architectures with what each gains and costs,
- the residual gaps none of them close,
- what would falsify the lean candidate.

It exists so a future session can continue the discussion without re-deriving it.

## What this document is not

- **Not a decision.** No option has been chosen. The user has not approved any of them.
- **Not a plan.** There are no steps, owners, or timelines here. Planned architectures
  live in `docs/`; implementation plans do not exist for any candidate.
- **Not verified findings.** The `[L1]` items below were read directly from primary
  sources in the sessions cited, but everything about *how the pieces compose* is
  `[U]` — untested inference. `NOTES.md` is the home for verified findings; this file is
  not that.
- **Not a benchmark or cost analysis.** No latency, memory, throughput, or effort
  numbers appear here; none were measured.
- **Not a claim about the current stack's correctness.** It says nothing about whether
  the shipped Docker workflow is wrong — only that its complexity exists to serve
  Docker-on-macOS problems that this Linux host does not have.

## The question

"Give a coding agent its own machine: persistent, N panes, detachable, local and
EU-neutral, with a thin host terminal." If that were the only requirement — no
inherited Docker recipes — what fits best?

## Premises

**Verified `[L1]`:**

- This dev host is Ubuntu 26.04.1 x86_64, kernel 7.0.x, UID 1000, `/dev/kvm` present
  (`root:kvm`), `vmx` in `/proc/cpuinfo`. Docker Engine present.
- The current container (`pi-agent-herdr:node22`) has **no `/dev/kvm`, no `/dev/fuse`**,
  no `SYS_ADMIN` in `CapEff=00000000a80425fb`, Node v22.23.4, pi 1.4.0.
- Gondolin: Linux host uses KVM and "Requires access to `/dev/kvm`"; TCG fallback exists
  but is "much slower and is not the recommended mode"
  (`gondolin/docs/qemu.md`).
- Gondolin: "Each attached client gets an independent command channel; concurrent
  attaches do not share request IDs or cross-talk between exec streams"
  (`gondolin/docs/cli.md`).
- Gondolin mediates egress in userspace: no generic NAT, unknown TCP blocked, `CONNECT`
  denied, internal ranges blocked by default, synthetic DNS by default, TLS MITM with a
  host-side CA trusted inside the guest (`docs/network.md`, `docs/limitations.md`).
- Gondolin secrets: `createHttpHooks({allowedHosts, secrets})` returns `{httpHooks, env}`;
  the guest sees placeholders; substitution applies to exact placeholder bytes in
  outbound headers (query strings when enabled); a placeholder used against a disallowed
  host blocks the request (`docs/secrets.md`).
- pi's Gondolin extension overrides the built-in tools `read`, `write`, `edit`, `bash`,
  `grep`, `find`, `ls`; commands inherit the host environment unless changed, and pi's
  docs warn not to treat the pattern as a credential boundary as shipped
  (`pi/docs/containerization.md`; `examples/extensions/gondolin/index.ts`).
- OpenShell: only the canonical main process has one stdin owner; `sandbox exec --tty --
  /bin/bash -l` is the documented way to get "a new independent shell" (v0.1.5 docs).
- OpenShell: credentials exist as opaque placeholders; the proxy substitutes the real
  value "only after network policy and endpoint binding both pass"; in v0.1.5 the
  workspace-global managed inference route was removed, so workloads call the provider's
  native endpoint.
- OpenShell: the docker driver reaches the host Docker daemon over
  `/var/run/docker.sock`; the podman driver is rootless (Podman 5.x, cgroups v2, user
  socket); bind mounts exist but are warned against as isolation bypasses.
- A host-native herdr server is a real, existing setup (the repo records the
  `EADDRINUSE` conflict when a container herdr shares the host's socket path).

**Unverified `[U]`:**

- Whether the Gondolin host process can run inside a Docker container with
  `--device /dev/kvm` (no Gondolin doc mentions containers).
- Whether herdr's server can be a Gondolin client / drive panes against one VM.
- Whether herdr 0.9.x runs natively on this Ubuntu host (the same linux/amd64 binary
  runs in the container; not tested on the host here).
- Whether SSE/streaming survives Gondolin's mediator (docs say responses are streamed or
  buffered "depending on hooks", without naming streaming APIs).
- Whether a custom Gondolin rootfs still receives the MITM CA.
- Whether the pi example (pinned 0.12.0) runs unchanged on Gondolin ≥0.13.0.
- Whether a herdr-style multiplexer works as an OpenShell canonical main process.

## The fork

The decision collapses to one question: **sandbox the agent process, or only the code it
executes?**

- **Tool-scope** — pi runs natively; all seven built-in tools execute in a micro-VM.
  This covers where untrusted content becomes action, because prompt injection can only
  read or execute through those tools.
- **Process-scope** — the whole pi process sits inside a boundary, so `~/.pi`,
  extensions, and pi's own model calls are contained as well.

Most of the current stack (named volume, socket/rename workarounds, UID mapping, sshd,
web bridge) serves Docker-on-macOS, not the stated requirement.

## Candidate A — lean, host-native (tool-scope) `[U]`
```
herdr server  (native, host)        ← panes, detach/reattach, persistence
  └── pi      (native, host)        ← agent brain; holds only a placeholder key
        ├── LiteLLM proxy (host)    ← holds the real provider key
        └── Gondolin micro-VM       ← all built-in tools execute here
              ├── VFS: per-path ro/shadow, symlink-escape blocked
              ├── mediated egress: no NAT, unknown TCP blocked, synthetic DNS,
              │   internal ranges blocked by default
              └── createHttpHooks: guest secrets as placeholders, header substitution
```

Why it fits this host `[U]`: KVM is present, so Gondolin runs with hardware acceleration
and needs no container runtime at all. Every macOS workaround disappears, and concurrent
`gondolin attach` matches herdr's pane model.

Gains: tool execution in a hypervisor-grade VM; egress that classifies protocols and
blocks the rest; secret substitution so `git push` or `curl` inside the guest never sees
the real token.

Does **not** gain:

- pi's own model calls happen on the host, so Gondolin's broker does not protect them —
  hence LiteLLM in front. Without it, pi holds the real provider key.
- pi's host process can still read `~/.pi`, `~/.ssh`, `~/dev` — the same residual gap the
  current container has.
- Gondolin is young (0.14.0), Alpine-only images, HTTP/1.x only; the shipped pi example
  wires no secrets, so `createHttpHooks` is code we would write and own.

## Candidate B — process-scope, OpenShell `[U]`

```
OpenShell gateway (host, docker or podman driver)
  └── sandbox per pi agent   ← Landlock paths, deny-by-default egress,
                                provider-brokered credentials, non-root/no-caps
herdr (outside)              ← panes attach via `sandbox exec --tty`
```

Gains: the strongest posture available — the key never exists inside the sandbox, policy
is enforced in-kernel, egress is deny-by-default with binary + endpoint binding.

Costs: it is a platform, not a library (gateways, workspaces, providers, profiles,
policy), at v0.1.5. The herdr integration is the weak link: `exec --tty` concurrency is
documented, but a multiplexer as canonical main process is not.

## Candidate C — plain Docker, hardened `[L1]`

The known-working baseline: one container, `--cap-drop ALL`, non-root, no sshd, narrowed
mounts, squid egress sidecar, LiteLLM sidecar. Proven end-to-end today. Its value is a
real container boundary and reproducibility across machines; it cannot express per-path
policy or broker credentials by itself.

## Candidate D — Candidate A with a remote execution arm `[U]`

If the execution arm should live on another machine, **Gondolin cannot do it today** (no
remote transport: local Unix socket plus in-process QEMU). The piece that exists for
remote execution is `@earendil-works/pi-env`: a Rust daemon deployed over SSH, speaking a
framed protocol on stdin/stdout — file ops, `exec`, `pty`, `watch`, `listFiles`, no
listening port.

```
herdr server (host)  →  pi (host)  →  pi-env daemon (remote machine)
```

`[L1]` pi-env is **not a sandbox** and is **not wired to the pi coding agent**: it is the
`ExecutionEnv` backend for Pi Durable, and the CLI has no such hook. Bridging it would be
our own extension.

The trade is threat model, not configuration: pi-env trusts the remote machine; Gondolin
treats the guest as adversarial. A remote *sandboxed* arm would need pi-env for execution
plus a policy layer it does not provide.

## Residual gaps, by candidate

| Gap | A | B | C |
|---|---|---|---|
| Agent process can read host secrets | **open** | closed | closed (narrowed mounts) |
| Per-path filesystem policy | closed (VFS) | closed (Landlock) | open |
| Model-call credential brokering | via LiteLLM | native | via LiteLLM |
| Deny-by-default egress | closed (no NAT) | closed | partial (sidecar) |
| Protocol coverage | HTTP/1.x only | broad | broad |
| Multi-pane detach/reattach | closed | `[U]` | closed |
| Maturity | young | young (0.1.5) | proven |

## Falsifiers for Candidate A

- Gondolin's host process cannot run alongside herdr on this host (pane reachability
  untested).
- The model API requires HTTP/2 or streaming the mediator cannot carry.
- The Alpine guest cannot host the toolchain the agent needs.

Both are cheap to test before committing to anything.

## Provenance

- `agent/research/X3-openshell-targeted.md` — OpenShell primary-source detail.
- `agent/research/X4-gondolin-targeted.md` — Gondolin primary-source detail.
- `NOTES.md` § "Sandbox complements — OpenShell / Gondolin (2026-10-24)" — compact
  verified summary.
- `docs/market-research-agentic-sandboxes.md` — wider landscape (untracked).
