# UC2 on OpenShell: git push from a mount-less sandbox, token stays host-side

as-of: 2026-11-11 · host: pluto · OpenShell 0.1.8, MicroVM driver · **result: PASS**

## Summary

- Plain `git clone` / `commit` / `git push` over HTTPS worked from inside a sandbox with
  **no host mounts**. Branch `openshell-uc2-test-20261111` (commit `97c3e33`) is on
  GitHub; left there for the lead to decide.
- The sandbox only ever saw a placeholder (`GITHUB_TOKEN=openshell:resolve:env:v…`, 56
  chars). The proxy swapped in the real fine-grained PAT host-side.
- Egress: only `git` → `github.com:443` → `cgint/pi-herdr-docker.git` smart-HTTP paths.
  Everything else was denied, proven by data and by OCSF log lines.
- Same outcome as the sbx UC2 test. OpenShell is narrower: the credential and the egress
  are bound to one binary (`/usr/bin/git`) and to one repo's paths (L7).

## How injection was configured

- Profile `uc2-profile-github-push.yaml` is a custom provider profile adapted from NVIDIA's
  `providers/github.yaml`. It sets `auth_style: basic` and `env_vars: [GITHUB_TOKEN]`, and
  has one endpoint, `github.com:443` (`protocol: rest`, `enforcement: enforce`). That
  endpoint allows three rules only:
  - `GET  /cgint/pi-herdr-docker.git/info/refs*`
  - `POST …/git-upload-pack`
  - `POST …/git-receive-pack`

  `binaries: [/usr/bin/git]`. `git-remote-http` matches by ancestry.
- **Why not the stock github profile:** it is not built in (`profile describe github`
  returned "not found"). Its upstream version injects `bearer`, and it denies
  `git-receive-pack`.
- The provider was created with
  `GITHUB_TOKEN="$(tr -d '\n' < FILE)" openshell provider create --name uc2-gh --type uc2-github-push --from-existing`.
  The token went into the CLI's environment only. It never appeared in argv or output.
- Inside the sandbox, an inline credential helper hands the placeholder to git as the
  password:

  ```
  !f(){ echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f
  ```

  git sends `Authorization: Basic base64(x-access-token:<placeholder>)`. The proxy
  decodes it, resolves the placeholder, and re-encodes it. No token, `.netrc` or helper
  config was written to disk (`git config credential.helper` lines: 0).
- Policy `uc2-policy.yaml` has Landlock filesystem rules and **no network rules of its
  own**. The only network policy, `_provider_uc2_gh`, comes from the provider (seen in
  `policy get --full`). The sandbox was created with `--provider uc2-gh` and no
  `--driver-config-json`, so it has no virtiofs mounts.

## Steps (reproducible)

```
. spike/openshell/env.sh; setsid nohup openshell-gateway >"$OS_ROOT/gateway.log" 2>&1 </dev/null &
openshell provider profile lint   -f spike/openshell/uc2-profile-github-push.yaml
openshell provider profile import -f spike/openshell/uc2-profile-github-push.yaml
GITHUB_TOKEN="$(tr -d '\n' < <token-file>)" openshell provider create --name uc2-gh --type uc2-github-push --from-existing
openshell sandbox create --name os-uc2 --from pi-herdr-sbx:spike --policy spike/openshell/uc2-policy.yaml \
  --provider uc2-gh --detach --no-tty -- sleep infinity
openshell sandbox upload os-uc2 spike/openshell/uc2-inside.sh /sandbox/
openshell sandbox exec -n os-uc2 --no-tty -- bash /sandbox/uc2-inside.sh
# cleanup
openshell sandbox delete os-uc2; openshell provider delete uc2-gh; openshell provider profile delete uc2-github-push
pkill -TERM -f bin/openshell-gateway
```

## Results

| Check | Result | Evidence |
|---|---|---|
| clone (public repo) | ✅ | rc=0 |
| commit + `git push -u` (`GIT_TERMINAL_PROMPT=0`) | ✅ | `* [new branch] openshell-uc2-test-20261111`; OCSF `ALLOWED POST https://github.com/cgint/pi-herdr-docker.git/git-receive-pack [policy:_provider_uc2_gh engine:l7]`; host `git ls-remote` shows `97c3e33…` |
| Token not inside: hash | ✅ | sha256[:12] of `$GITHUB_TOKEN` inside = `6e175a0e968d`; of the host token file = `90c6522d2bc3` |
| Token not inside: grep `github_pat_` | ✅ | env: 0. `/proc/*/environ`: 0. `/etc`: 0. `/tmp`: 0. `/sandbox`: 1 file, the probe script itself (it contains the literal pattern). Full pattern `github_pat_[A-Za-z0-9_]{20,}` across all four: 0 |
| Egress denied | ✅ | `curl` to example.com, gitlab.com, api.github.com: `000` (`transparent_tcp_policy_denied`, `policy_dns_ineligible`). `curl https://github.com/`: `000` (curl is not in the binaries list). `git ls-remote` of another GitHub repo (octocat/Hello-World): **403** (`L7_REQUEST deny`). `git ls-remote` of gitlab.com: connection refused |
| Host-side plaintext | ✅ | The full token string appears 0 times in `gateway.log` and in the VM rootfs cache. One `github_pat_` hit in `gateway.log` is the `command_preview` of the grep command, not the token |

## Notes / caveats

- `api.github.com` was not needed for git push, so it stayed denied. `gh` / API use
  would need a second endpoint with `bearer` placement (untested here).
- The credential helper lives in the git command line, not on disk. A real agent setup
  would put it in `/sandbox/.gitconfig`. That file holds only the placeholder reference
  `$GITHUB_TOKEN`, so it is safe.
- Not tested: whether `auth_style: bearer` (the stock profile) also works for git smart
  HTTP on github.com.
- State after the test: sandbox, provider and profile deleted, gateway stopped. The
  pre-existing `canary-echo` profile was left untouched.
