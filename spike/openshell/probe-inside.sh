#!/usr/bin/env bash
# Blast-radius probes run INSIDE an OpenShell sandbox:
#   openshell sandbox upload <sbx> spike/openshell/probe-inside.sh /sandbox/
#   openshell sandbox exec -n <sbx> --no-tty -- bash /sandbox/probe-inside.sh OSCANARY-
# Prints one PASS/FAIL line per check; "PASS" = the restriction held (or, for ALLOW
# lines, the intended access works). Egress is tested by DATA, not by TCP connect.
# Mirrors spike/sbx/probe-inside.sh; paths match spike/openshell/policy-spike.yaml.
set -uo pipefail
CANARY_PREFIX="${1:?canary prefix}"

check() { # name, command that must FAIL (non-zero) for the restriction to hold
  local name="$1"; shift
  if timeout 10 "$@" >/dev/null 2>&1; then echo "FAIL $name"; else echo "PASS $name"; fi
}
allow() { # name, command that must SUCCEED
  local name="$1"; shift
  if timeout 20 "$@" >/dev/null 2>&1; then echo "PASS(allow) $name"; else echo "FAIL(allow) $name"; fi
}

echo "== T1 secrets out of sight"
if grep -rqsE -- "${CANARY_PREFIX}[0-9a-f]{32}" /proc/[0-9]*/environ /sandbox /etc /tmp 2>/dev/null; then
  echo "FAIL T1 canary value found inside sandbox"
else
  echo "PASS T1 canary value not found in environ//sandbox//etc//tmp"
fi
echo "INFO T1 CANARY_KEY in env = ${CANARY_KEY:-<unset>}"
echo "INFO T1 curl -> pluto:40199 with placeholder: $(timeout 10 curl -sS -H "Authorization: Bearer ${CANARY_KEY:-x}" http://pluto:40199/t1 2>&1 | head -c 200)"
echo "INFO T1 python -> pluto:40199 with placeholder (binary not in profile): $(timeout 10 python3 -c 'import os,urllib.request as u; print(u.urlopen(u.Request("http://pluto:40199/t1py",headers={"Authorization":"Bearer "+os.environ.get("CANARY_KEY","x")}),timeout=8).read().decode().strip())' 2>&1 | tail -1 | head -c 200)"

echo "== T2a binary scoping"
check "T2a curl -> home-llm (only node is allowed)" curl -fsS -m8 http://pluto:40115/v1/models

echo "== T3 egress"
check "T3 https example.com (not allowlisted)" curl -fsS -m8 https://example.com
check "T3 http example.com"                    curl -fsS -m8 http://example.com
check "T3 https 1.1.1.1 (data)"                curl -fsS -m8 https://1.1.1.1/
check "T3 raw tcp 8.8.8.8:53 (dns reply)"      bash -c 'exec 3<>/dev/tcp/8.8.8.8/53; printf "\x00\x1c\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01" >&3; [ -n "$(head -c 2 <&3)" ]'
# OpenShell answers every name with a synthetic 198.18.0.0/15 address (policy DNS) and
# logs unapproved names as NET:REFUSE policy_dns_ineligible. Fail only on a REAL address.
check "T3 dns exfil lookup (real address)"     bash -c 'a=$(getent hosts "exfil-test-$RANDOM.example.org" | cut -d" " -f1); [ -n "$a" ] && [[ "$a" != 198.18.* && "$a" != 198.19.* ]]'
check "T3 node fetch example.com (node is allowed only for pluto:40115)" node -e 'fetch("https://example.com").then(r=>r.text()).then(t=>process.exit(t.length>0?0:1)).catch(()=>process.exit(1))'

echo "== T4 host / LAN reach"
check "T4 docker socket usable"                bash -c 'test -S /var/run/docker.sock && curl -s --unix-socket /var/run/docker.sock http://x/info | grep -q ServerVersion'
check "T4 host ssh banner pluto:22"            bash -c 'exec 3<>/dev/tcp/pluto/22; [ -n "$(head -c 4 <&3)" ]'
check "T4 host.openshell.internal:22 banner"   bash -c 'exec 3<>/dev/tcp/host.openshell.internal/22; [ -n "$(head -c 4 <&3)" ]'
check "T4 LAN gateway 192.168.1.1:80 (http)"   curl -fsS -m8 http://192.168.1.1/
check "T4 cloud metadata 169.254.169.254"      curl -fsS -m8 http://169.254.169.254/
check "T4 host ~/.pi visible"                  test -e /home/cgint/.pi/agent/auth.json
check "T4 host ~/.ssh visible"                 test -e /home/cgint/.ssh

echo "== T5 filesystem"
check "T5 write /etc (ro by policy)"           touch /etc/os-probe
check "T5 write /usr/local (ro by policy)"     touch /usr/local/os-probe
check "T5 read / listing (not in policy)"      ls /
check "T5 read /opt (not in policy)"           ls /opt
check "T5 write /hostro (virtiofs read_only)"  touch /hostro/os-probe
allow "T5 read /hostro/file.txt"               cat /hostro/file.txt
allow "T5 write /sandbox (workdir rw)"         touch /sandbox/os-probe-workdir

echo "== T9 nested ro/rw + hide"
check "T9 write /hostdev top (ro by Landlock)" touch /hostdev/os-probe-top
check "T9 write /hostdev/repoB (ro)"           touch /hostdev/repoB/os-probe
allow "T9 read /hostdev/repoB/README"          cat /hostdev/repoB/README
allow "T9 write /hostdev/repoA (rw hole)"      touch /hostdev/repoA/os-probe-rw
check "T9 read /hostdev/repoA/.env (hidden?)"  cat /hostdev/repoA/.env
