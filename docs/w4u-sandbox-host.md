# w4u as a sandbox host: sbx + NVIDIA OpenShell

as-of: 2026-11-11 · status: **sbx 0.51.0 installed and logged in; T1–T5, pi → home-llm and the UC2 git round trip pass. OpenShell 0.1.8 installed user-locally; MicroVM blast-radius checks all pass on w4u, pi → home-llm works over Tailscale. Nothing left running.** · NOT a decision

## Summary

- **w4u can run both sandboxes.** It is a world4you Plesk VPS (production), Ubuntu 24.04.5,
  kernel 6.8, 4 vCPU, 7.7 GiB RAM, no swap. Nested KVM works: OpenShell booted libkrun
  microVMs, and `sbx diagnose` reports `/dev/kvm is accessible`.
- **sbx:** installed from the release .deb (54 new packages, 0 upgraded, 0 removed). It
  runs as root with no complaint. `sbx version` → v0.51.0; `sbx ls` → `not signed in to
  Docker`. Not tested further: `sbx login` needs the user's browser.
- **OpenShell:** the same results as on pluto (T1, T2a, T3, T4, T5, T6, T9). Cold create
  took 143 s; warm create 4 s; restart 5 s. A running sandbox (herdr + one pi) cost about
  **+450 MiB host RAM**, with VM memory capped at 2 GiB.
- **Two w4u-specific findings:**
  1. A policy rule naming the short name `pluto` fails on w4u
     (`policy_dns_upstream_error_response`). OpenShell's policy DNS ignores the host's
     `search tail90880f.ts.net`. Use the FQDN `pluto.tail90880f.ts.net`.
  2. `host.openshell.internal:<port>` reaches the host's **127.0.0.1** services. The
     canary echo server bound to loopback received the real canary. On this server any
     rule naming `host.openshell.internal` exposes loopback services such as ollama
     `:11434` and `:5000`. Without a rule they are denied (verified).

## Install log (everything added) and how to undo

| Added | What | Undo |
|---|---|---|
| apt: `docker-sbx` 0.51.0 | `/usr/bin/sbx`, `/usr/libexec/{containerd-shim-nerdbox*,docker-docklet,mkfs.*,nerdbox-*,sailor-*,lib/libsailor.so}` (setuid: `containerd-shim-nerdbox-gpu-v1`) | `apparmor_parser -R /etc/apparmor.d/docker-sbx-nerdbox-shim`, then `apt-get purge docker-sbx` |
| apt: 53 deps (all auto-marked) | gnome-keyring + GTK3/4, gcr, dconf, p11-kit, libsecret, mesa-free libs; list in `/root/sbx-install/new-packages.txt` | `apt-get autoremove --purge --simulate` first, then the same without `--simulate` |
| AppArmor | `/etc/apparmor.d/docker-sbx-nerdbox-shim` (conffile, loaded by postinst: `unconfined` profiles for nerdbox shim + docklet so they may create userns) + empty `/etc/apparmor.d/local/docker-sbx-nerdbox-shim` | removed by `purge` (unload first, see above) |
| sbx user state | `/root/.config/com.docker.sandboxes/` (empty auth store), `/root/.local/state/sandboxes/` | `rm -r` both |
| install media | `/root/sbx-install/` (sbx .deb, `new-packages.txt`, `apt-install.log`, `dep-debs/` = 53 downloaded deps, `ctl/`) | `rm -r /root/sbx-install` |
| OpenShell binaries | `/root/.local/opt/openshell-0.1.8/{bin/openshell,bin/openshell-gateway,bin/openshell-prover,libexec/openshell/openshell-driver-vm}` (213 MB), extracted from `openshell_0.1.8-1_amd64.deb`; sha256 `b3339527…a656b1` matches the release checksum file | `rm -r /root/.local/opt/openshell-0.1.8` |
| OpenShell state | `/root/.local/share/openshell-spike/` (gateway.toml, TLS/JWT, SQLite DB, VM image cache; 4.4 GB) | `rm -r /root/.local/share/openshell-spike` |
| OpenShell install media | `/root/openshell-install/` (.deb, `extract/`, `image/Dockerfile`, `image/build.log`) | `rm -r /root/openshell-install` |
| spike files | `/root/openshell-spike/` (env.sh, policy, profile, probes, echo-server.py, fixtures, logs) | `rm -r /root/openshell-spike` |
| Docker image | `pi-herdr-sbx:spike` (2.17 GB, from `spike/sbx/Dockerfile`), plus the `sbx/shell-image` base layers in the BuildKit cache | `docker image rm pi-herdr-sbx:spike`. Don't prune the shared builder cache blindly. |

Not touched: Plesk, web/mail, the Docker daemon, firewall, existing containers/networks/volumes
(26 containers still running, `systemctl --failed` is empty). Before and after the
install, needrestart reported "No services need to be restarted". No users created, no
systemd units, no linger. Started on demand and still idle: root's per-user D-Bus session
bus (socket-activated when `sbx` ran).

**Install choices:**
- `--no-install-recommends` because the default pulls 100 packages, including
  `libpam-gnome-keyring` (it would edit the PAM login stack on a production host). None of the 54
  ships a system unit, init script or `pam-configs` entry (checked by unpacking).
- The echo server bound to 127.0.0.1 (the repo version binds 0.0.0.0, which would be public here).
- OpenShell gateway: plain background process, not the packaged user systemd unit.
  Certs come from `openshell-gateway generate-certs --output-dir $OPENSHELL_LOCAL_TLS_DIR
  --server-san host.openshell.internal`, then `openshell gateway add https://127.0.0.1:17670 --local`.
  `spike/openshell/env.sh` skips both steps, so they're needed on a fresh host.

## sbx status

| Check | Result | Evidence |
|---|---|---|
| install | ✅ | `docker-sbx 0.51.0-1~ubuntu.24.04~noble`; 0 upgraded / 54 new / 0 removed |
| runs as root | ✅ (CLI level) | `sbx version` → `v0.51.0 7d55286…`; no root refusal. The only root-related string in the binary is about an image `USER` it can't resolve. |
| `sbx ls` | ✅ expected | `Error: not signed in to Docker` |
| `sbx diagnose` | ✅ | Virtualization ✓ (`/dev/kvm is accessible`), mkfs ✓, 168 GiB free. Daemon not running (not started on purpose). Notes v0.53.0 is out. |
| sandbox run as root | ✅ | After `sbx login` (user, 2026-11-11): sandbox `uc2` created in 32 s with `--memory 2g`. Note: the **primary** workspace must be read/write ("primary workspace must be read/write"), so put a throwaway rw dir first and the `:ro` mounts after it. |
| T1 secret out of sight | ✅ | `set-custom` canary toward a loopback echo server (bound to 127.0.0.1): `real_canary_received=True`; probe grep inside found nothing |
| T3 egress deny (by data) | ✅ | example.com http/https, 1.1.1.1:443, DNS-over-TCP to 8.8.8.8, DNS exfil: all PASS |
| T4 host/LAN reach | ✅ | no host docker socket, no host SSH banner, no LAN, no host home dirs |
| T5 ro mount | ✅ | write into the `:ro` workspace denied |
| T2a pi → home-llm | ✅ (2nd try) | via Tailscale `pluto.tail90880f.ts.net:40115` with one allow rule; the first `pi -p` returned nothing after model discovery, the retry answered `SBX-W4U-PI-OK`. Cause of the first miss not determined |
| UC2 git round trip | ✅ | token piped over SSH stdin into `sbx secret set github --sandbox uc2 -f` (never in args or files); mountless clone → commit → `git push` of branch `sbx-uc2-w4u-test-20261111`; VM sees only `gho_sbxproxymanaged…`, 0 `github_pat_` hits |
| RAM | ok | `free -m` used 2902 → 3379 MiB with the sandbox running (+~480 MiB) |

## OpenShell tests (w4u, OpenShell 0.1.8, `compute_driver = "vm"`, 2 vCPU / 2048 MiB / 8 GiB overlay)

Image: `pi-herdr-sbx:spike` built on w4u (pi 1.5.2, herdr 0.9.2). Policy:
`spike/openshell/policy-spike.yaml`, unchanged. Probe: `spike/openshell/probe-inside.sh`,
adapted for w4u: canary via `host.openshell.internal:40199`; LAN checks replaced with docker
bridges, public IP and loopback ollama; host paths under `/root`.

| Test | Result | Evidence |
|---|---|---|
| T1 secret out of sight | ✅ | Random canary generated on w4u (never printed, file deleted afterwards), stored via `provider create --from-existing`. Inside: `CANARY_KEY=openshell:resolve:env:v…_CANARY_KEY`. Echo server logged `real_canary_received=True` for curl. A grep of `/proc/*/environ`, `/sandbox`, `/etc` and `/tmp` found no canary. python3 got `EACCES`, logged as `DENIED /usr/bin/python3.14 … transparent_tcp_policy_denied`. |
| T2a pi → home-llm | ✅ | `curl -m5 http://pluto:40115/v1/models` from the w4u host returned 200 over Tailscale (`pluto` → 100.79.153.100). Inside, the short name failed in policy DNS. Live-added `pluto.tail90880f.ts.net:40115` for `/usr/bin/node` only (policy v2, no restart). `pi -p` printed `W4U-OPENSHELL-PI-OK` in 4 s. **curl to the same FQDN:port was denied:** `DENIED /usr/bin/curl … transparent_tcp_policy_denied`. |
| T3 egress deny (by data) | ✅ | Denied, each with an OCSF line: https/http example.com, `https://1.1.1.1`, a raw DNS query to 8.8.8.8:53, node fetch of example.com. An unknown name gets `policy_dns_ineligible`, no real address. herdr's own update check to `herdr.dev` was denied too. |
| T4 host / net reach | ✅ | Docker socket absent. Denied: `host.openshell.internal:22` and `:11434` (`transparent_tcp_mapping_denied`), docker bridges `172.17.0.1:80` and `172.18.0.1:80`, host public IP `212.227.128.145:443`, `169.254.169.254`, tailnet `pluto:22`. Host `/root/.pi` and `/root/.ssh` aren't visible. |
| T5 FS read-only | ✅ | `/etc` and `/usr/local` not writable. `/` and `/opt` not listable. virtiofs `read_only` mount not writable; reading it works. `/sandbox` writable. |
| T9 nested ro/rw | ✅ | `/hostdev` top and repoB read-only; repoA writable, and the write reached the host. The first run failed: the root-owned fixture wasn't writable by VM uid 1000 (virtiofs keeps host perms). After `chown 1000:1000` it passed. On w4u uid/gid 1000 = `cgint:psaadm` (a Plesk group); only the throwaway fixture dir was chowned. |
| T9 hide `.env` in a rw repo | ⚠️ | Readable, as on pluto (Landlock has no deny rules). Known gap. |
| T6 herdr + one pi alive | ✅ | Main process `herdr server` (status running, protocol 22). Workspace `w4u-os`, `herdr agent start pi1 --kind pi`, `agent prompt --wait` → pane shows `W4U-OPENSHELL-PI-OK`. `ps`: `herdr server` + `pi`. |
| stop/start | ✅ | stop 1 s, start → Ready 5 s; herdr server relaunched. pi didn't resume because the herdr `pane_history` config + pi integration weren't installed in this run (verified on pluto). |
| sbx-style tests (T2b, T7, T8) | ⏳ | not run |

## Resources / performance

| Metric | Value |
|---|---|
| Baseline before anything (`free -m`) | used 2787 MiB, available 5107 MiB |
| After installing sbx, before OpenShell | used 2863, available 5030 |
| herdr + pi sandbox running | used 3341, available 4552 → **≈ +450 MiB** host; guest sees 2026 MiB total, 199 MiB used |
| OpenShell processes RSS | gateway 160 MiB, VM (libkrun) 370 MiB, host runtime 49, driver 37, supervisor 10 → **≈ 630 MiB** total |
| After everything stopped | used 2818, available 5075 (back to baseline) |
| Cold create (first image import, 2.17 GB image) | **143 s** to Ready (export ~48 s, rootfs ~79 s, overlay ~139 s) |
| Warm create (cached image) | **4 s** to Ready |
| stop / start | 1 s / 5 s |
| Image build on w4u | 80 s |
| Disk | OpenShell state 4.4 GB, binaries 213 MB, image 2.17 GB, sbx package 330 MB + deps |
| Load during cold create | load avg ≤ 1.5 (4 vCPU) |

The 2 GiB `mem_mib` is a ceiling, not a reservation. libkrun RSS grows as the guest touches
memory. With no swap and ~5 GiB available, 2–3 such sandboxes at once fit; a heavy pi
workload (npm builds) could push RSS toward 2 GiB per VM.

## Production-safety notes

- The host has **no swap**. A VM that grows to its 2 GiB cap, multiplied by several
  sandboxes, could OOM production processes. Keep `mem_mib` ≤ 2048 and limit concurrent
  sandboxes.
- `host.openshell.internal` = host loopback. Never add a policy rule for it except for a
  specific, intended port.
- `enable_bind_mounts = true` + `resource_admission.enabled = false` were used for T5/T9
  (fixtures only). For real use on w4u, prefer upload/download or mount only dedicated dirs.
  NVIDIA warns that libkrun doesn't confine a compromised guest kernel to the mount source.
- The VM env includes `OPENSHELL_TELEMETRY_ENABLED=true` (seen in the driver argv). What
  is sent, and where, is unverified. No telemetry denials or allows appeared in the
  sandbox OCSF log.
- The `openshell sandbox create` CLI sat on "Waiting for VM supervisor" for ~9 min after
  the sandbox was already `Ready` (supervisor session accepted at +143 s), then exited.
  The cause is unknown; for the warm create the CLI was killed once Ready was reached, so it's unknown whether it hangs there too. Check readiness with `sandbox list`/`get`.
- The gateway was run with `setsid` (spike only). Sandboxes die with the gateway (pluto
  finding), so a supervised unit is needed for real use.

## Open items

1. sbx: login done and T1–T5 + UC2 passed as root (2026-11-11). Decide whether root is
   acceptable long-term or a dedicated user in group `kvm` is wanted (requires creating a user).
   The GitHub token is now in sbx's root-only file store on w4u (no keychain); remove it with
   `sbx secret rm github --sandbox uc2` when done (it expires 2026-11-18 anyway).
2. sbx v0.53.0 is available. Upgrade only after deciding to keep sbx.
3. OpenShell telemetry: find out what `OPENSHELL_TELEMETRY_ENABLED` sends; disable it if possible.
4. Supervised gateway on w4u (user systemd + linger for root, or a system unit), if kept.
5. pi resume across stop/start on w4u (upload `herdr-config.toml` with `pane_history = true`
   + `herdr integration install pi`). Verified on pluto, not repeated here.
6. Update `spike/openshell/env.sh` docs: the cert generation + `gateway add` steps, and the
   FQDN for tailnet hosts.
