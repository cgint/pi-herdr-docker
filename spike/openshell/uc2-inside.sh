#!/usr/bin/env bash
# UC2 (inside the sandbox): clone, branch, empty commit, push; then token-presence checks.
# git gets the PLACEHOLDER from $GITHUB_TOKEN via an inline credential helper.
set -uo pipefail
BR="${1:-openshell-uc2-test-20261111}"
cd /sandbox && rm -rf pi-herdr-docker
export GIT_TERMINAL_PROMPT=0
HELPER='!f(){ echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f'
echo "== clone";  git clone https://github.com/cgint/pi-herdr-docker.git 2>&1 | tail -2; echo "rc=${PIPESTATUS[0]}"
cd pi-herdr-docker || exit 1
git checkout -b "$BR"
git -c user.name="openshell uc2 test" -c user.email="openshell-uc2@example.invalid" \
  commit --allow-empty -m "test: push from inside OpenShell sandbox (uc2), safe to delete"
echo "== push"; git -c credential.helper= -c credential.helper="$HELPER" push -u origin "$BR" 2>&1 | tail -4; echo "rc=${PIPESTATUS[0]}"
git log -1 --format='HEAD %H'
echo "== token checks"
echo "GITHUB_TOKEN placeholder prefix: ${GITHUB_TOKEN%%_*}... (len ${#GITHUB_TOKEN})"
echo "sha12(GITHUB_TOKEN inside) = $(printf %s "$GITHUB_TOKEN" | sha256sum | cut -c1-12)"
echo "github_pat_ hits env:            $(env | grep -c github_pat_)"
echo "github_pat_ hits /proc/*/environ: $(grep -las github_pat_ /proc/[0-9]*/environ 2>/dev/null | wc -l)"
for d in /sandbox /etc /tmp; do echo "github_pat_ hits $d (files): $(grep -rlas github_pat_ $d 2>/dev/null | wc -l)"; done
echo "git config credential lines: $(git config --show-origin --get-all credential.helper | wc -l)"
echo "== egress (data)"
for u in https://example.com https://gitlab.com https://api.github.com/ https://github.com/; do
  echo "curl $u -> $(curl -sS -m8 -o /dev/null -w '%{http_code}' "$u" 2>&1 | tail -1)"; done
echo "git ls-remote other repo -> $(timeout 20 git ls-remote https://github.com/octocat/Hello-World.git 2>&1 | tail -1 | head -c 160)"
echo "git ls-remote gitlab -> $(timeout 20 git ls-remote https://gitlab.com/gitlab-org/gitlab-foss.git 2>&1 | tail -1 | head -c 160)"
