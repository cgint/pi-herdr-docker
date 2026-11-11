#!/usr/bin/env bash
# Blast-radius probes run INSIDE the sandbox (sbx exec <name> bash /path/probe-inside.sh).
# Prints one PASS/FAIL line per check; "PASS" = the restriction held.
# Usage: probe-inside.sh <canary-prefix> <workspace-path>
set -uo pipefail
CANARY_PREFIX="${1:?canary prefix}"
WS="${2:?workspace path}"

check() { # name, command that must FAIL (non-zero) for the restriction to hold
  local name="$1"; shift
  if timeout 8 "$@" >/dev/null 2>&1; then echo "FAIL $name"; else echo "PASS $name"; fi
}

echo "== T1 secrets out of sight"
if grep -rqs -- "$CANARY_PREFIX" /proc/*/environ /home/agent /etc /tmp 2>/dev/null; then
  echo "FAIL T1 canary value found inside VM"
else
  echo "PASS T1 canary value not found in environ/home/etc/tmp"
fi
echo "INFO T1 CANARY_KEY in env = ${CANARY_KEY:-<unset>}"

echo "== T3 egress"
check "T3 https example.com (not allowlisted)" curl -fsS https://example.com
check "T3 http example.com"                    curl -fsS http://example.com
# Raw TCP: sbx's transparent proxy accepts connect() locally and denies upstream,
# so a bare connect "succeeds". Require actual bytes back instead.
check "T3 raw tcp 1.1.1.1:443 (https data)"    curl -fsS -m5 https://1.1.1.1/
check "T3 raw tcp 8.8.8.8:53 (dns reply)"      bash -c 'exec 3<>/dev/tcp/8.8.8.8/53; printf "\x00\x1c\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01" >&3; [ -n "$(head -c 2 <&3)" ]'
check "T3 dns exfil lookup"                    getent hosts exfil-test-$RANDOM.example.org

echo "== T4 host reach"
check "T4 host docker socket"                  test -S /var/run/docker.sock -a -n "$(curl -s --unix-socket /var/run/docker.sock http://x/info | grep -o ServerVersion)"
check "T4 host ssh banner (host:22)"           bash -c 'exec 3<>/dev/tcp/host.docker.internal/22; [ -n "$(head -c 4 <&3)" ]'
check "T4 LAN gateway 192.168.1.1:80 (http)"   curl -fsS -m5 http://192.168.1.1/
check "T4 host home ~/.pi visible"             test -e /home/cgint/.pi/agent/auth.json
check "T4 host ~/.ssh visible"                 test -e /home/cgint/.ssh

echo "== T5 filesystem"
echo spike > /home/agent/outside-workspace.txt && echo "INFO T5 wrote /home/agent/outside-workspace.txt (must not appear on host)"
check "T5 write into ro mount"                 touch "$WS/.sbx-ro-probe"
