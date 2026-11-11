# UC2 on OpenShell, repeated on w4u: git push from a mount-less sandbox, token host-side

as-of: 2026-11-11 · host: w4u (production web host) · OpenShell 0.1.8, MicroVM driver, 2 vCPU / 2048 MiB cap · **result: PASS**

## Summary

- Same result as on pluto (`uc2-git-push.md`). `git clone` / `commit` / `git push` over
  HTTPS worked from a sandbox with **no host mounts**. The fine-grained PAT stayed in
  OpenShell's host-side provider store. The sandbox only saw a 56-char placeholder.
- Branch `openshell-uc2-w4u-test-20261111` is on GitHub. HEAD is `7dcfafb` (author
  `openshell uc2 w4u test <openshell-uc2-w4u@example.invalid>`). It was left in place.
- Egress: only `git` → `github.com:443` → this repo's smart-HTTP paths. Everything else
  was denied, shown both by data and by OCSF log lines.
- Warm create took **4.3 s** to Ready. The running sandbox cost **≈ +270 MiB** of host
  "used" memory. Cleanup is complete: 0 openshell processes, and still 26 Docker containers.

## Deviation (honest note)

`uc2-inside.sh` hardcodes the pluto commit identity and message, and I ran it without
changing them. So the branch's first commit `1cb1b32` has author
`openshell uc2 test <openshell-uc2@example.invalid>` and message
"test: push from inside OpenShell sandbox (uc2), safe to delete". I did not rewrite
history or force-push. Instead I pushed a second empty commit, `7dcfafb`, with the
requested identity and message ("test: push from inside OpenShell sandbox on w4u (uc2),
safe to delete") as a fast-forward. Both commits are on the branch.

## Steps (as run on w4u)

```
# pluto → w4u: copy the unchanged uc2 files into /root/openshell-spike/
scp uc2-profile-github-push.yaml uc2-policy.yaml uc2-inside.sh w4u:/root/openshell-spike/
# w4u (all with: . /root/openshell-spike/env.sh)
setsid nohup openshell-gateway >>"$OS_ROOT/gateway.log" 2>&1 </dev/null &     # gateway.toml: mem_mib=2048
openshell provider profile lint   -f uc2-profile-github-push.yaml
openshell provider profile import -f uc2-profile-github-push.yaml
# token only via ssh stdin → CLI env; never argv, never a file on w4u, never in the sandbox
ssh w4u 'read -r GITHUB_TOKEN; export GITHUB_TOKEN; openshell provider create --name uc2-gh --type uc2-github-push --from-existing' < <token-file>
openshell sandbox create --name os-uc2 --from pi-herdr-sbx:spike --policy uc2-policy.yaml \
  --provider uc2-gh --detach --no-tty -- sleep infinity
openshell sandbox upload os-uc2 uc2-inside.sh /sandbox/
openshell sandbox exec -n os-uc2 --no-tty -- bash /sandbox/uc2-inside.sh openshell-uc2-w4u-test-20261111
# + second commit with the w4u identity, pushed the same way (inline credential helper)
# cleanup
openshell sandbox delete os-uc2; openshell provider delete uc2-gh; openshell provider profile delete uc2-github-push
kill -TERM <gateway pid>
```

## Results

| Check | Result | Evidence |
|---|---|---|
| clone (public repo) | ✅ | rc=0 |
| commit + `git push -u` (`GIT_TERMINAL_PROMPT=0`) | ✅ | `* [new branch] openshell-uc2-w4u-test-20261111`, then `1cb1b32..7dcfafb`. OCSF: `ALLOWED POST https://github.com/cgint/pi-herdr-docker.git/git-receive-pack [policy:_provider_uc2_gh engine:l7]`. `git ls-remote` from pluto: `7dcfafba…` |
| Token not inside: hash | ✅ | sha256[:12] of `$GITHUB_TOKEN` inside = `079be8fbc120` (placeholder `openshell:resolve:env:v…`, len 56). Host token file (`tr -d '\n' \| sha256sum`, computed on pluto) = `90c6522d2bc3` |
| Token not inside: grep | ✅ | Full pattern `github_pat_[A-Za-z0-9_]{20,}`: env 0, `/proc/*/environ` 0, `$HOME` (= `/sandbox`) 0, `/etc` 0, `/tmp` 0. The literal `github_pat_` matches only `/sandbox/uc2-inside.sh`, the probe script itself. `git config credential.helper` lines: 0 |
| Egress denied | ✅ | `curl` example.com / gitlab.com / api.github.com / github.com → `000`. OCSF: `DENIED <name> [reason:policy_dns_ineligible]` and `DENIED /usr/bin/curl(0) -> example.com:443 [reason:transparent_tcp_policy_denied]`. `git ls-remote` octocat/Hello-World → **403** (`DENIED GET …/Hello-World.git/info/refs [policy:_provider_uc2_gh engine:l7] [reason:L7_REQUEST deny …]`). `git ls-remote` gitlab.com → could not connect |
| Host-side plaintext | ✅ | The full token string appears 0 times in `gateway.log` and in 0 files under `$OS_ROOT/vm`. Checked with the token read from ssh stdin into `grep -F`, never printed |
| Provider create output | ✅ | `✓ Created provider uc2-gh`; `github_pat_` in the output: 0 |

## Timings / RAM (host `free -m`, w4u has no swap)

| Point | used MiB | available MiB |
|---|---|---|
| Before (gateway stopped) | 2901 | 4992 |
| Sandbox Ready (+~7 s) | 3076 | 4817 |
| During push / checks | 3171 | 4722 |
| After cleanup, gateway stopped | 2921 | 4972 |

- Create → Ready: **4.3 s** (warm; `Using cached root disk`).
- Process RSS during: gateway 121 MiB, libkrun VM 188 MiB, supervisor 50 MiB, driver 28 + 9 MiB.
- Guest: 2026 MiB total, 102 MiB used.

## Cleanup state

- Deleted: sandbox `os-uc2`, provider `uc2-gh` (and its stored credential), and profile
  `uc2-github-push`. The pre-existing `canary-echo` profile is untouched.
- Gateway stopped. `ps` shows no `openshell*` or `krun` processes. `docker ps -q | wc -l` = 26.
- The sbx sandbox `uc2` was not touched. No services, containers, apt or firewall were changed.
- Left on w4u: copies of `uc2-profile-github-push.yaml`, `uc2-policy.yaml`, `uc2-inside.sh`,
  `uc2-create.log` and `uc2-mem-before.txt` in `/root/openshell-spike/`. None of them holds the token.

## Oddities

- As on the earlier w4u run, the `sandbox create` CLI stayed on "Waiting for VM supervisor"
  after the sandbox was already Ready. It ran in the background under `timeout 300`.
  Readiness was checked with `sandbox list`.
- `pkill -TERM -f bin/openshell-gateway` (from the pluto steps) **does not match** on w4u. The
  gateway's argv is plain `openshell-gateway` because it was started via `PATH`. The pattern
  also matched and killed the ssh shell running the command, since that command line
  contained the pattern. Stop the gateway by PID instead.
