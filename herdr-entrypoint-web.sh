#!/bin/bash
# herdr-entrypoint-web.sh — additive web entrypoint for the herdr container.
#
# Sits ON TOP of the existing herdr-entrypoint.sh path: same sshd bootstrap, same
# `herdr server` lifecycle. The ONLY addition is an optional supervised
# herdr-web-bridge (browser UI) started BEFORE the server and kept up for its
# whole lifetime. Dispatch is runtime, not build-time:
#
#   HERDR_WEB=false   -> behaves exactly like herdr-entrypoint.sh (sshd + server)
#   HERDR_WEB=true    -> stage 1: herdr server ; stage 2: bridge (waits for the
#                      server socket, self-verifies via HTTP, then stays up for the
#                      server's whole lifetime)
#
# PID 1 (docker-init here, tini elsewhere) forwards SIGTERM; we trap it, tear the
# bridge down first, then let the server exit, and mirror the server's exit code.
# Children are detached via setsid so a stray signal to our process group cannot
# kill the supervisor mid-flight.
set -uo pipefail

BRIDGE_BIN="${HERDR_WEB_BRIDGE_BIN:-/usr/local/bin/herdr-web-bridge}"
WEB_PORT="${WEB_PORT:-8787}"
WEB_BIND="${WEB_BIND:-0.0.0.0}"   # docker-proxy relays 127.0.0.1:8787 via eth0
WEB_STATIC_DIR="${WEB_STATIC_DIR:-/opt/herdr-web/web-static}"
WEB_LOG="${WEB_LOG:-/tmp/herdr/bridge.log}"
HERDR_WEB="${HERDR_WEB:-false}"

BRIDGE_PID=""
SERVER_PID=""

teardown() {
  if [ -n "$BRIDGE_PID" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    kill -TERM "$BRIDGE_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
  fi
}

on_signal() {
  echo "herdr-entrypoint-web: caught SIG$1, tearing down" >&2
  teardown
  i=0
  while [ "$i" -lt 20 ]; do
    alive=0
    for p in "$BRIDGE_PID" "$SERVER_PID"; do
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null && alive=1
    done
    [ "$alive" = 0 ] && break
    sleep 0.25; i=$((i + 1))
  done
  exit 0
}

# --- sshd bootstrap: delegated to the existing entrypoint logic is NOT reused
# because that script exec's the server; replicate the idempotent parts only.
if dpkg -l openssh-server >/dev/null 2>&1; then
  if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    mkdir -p /etc/ssh
    ssh-keygen -A >/dev/null 2>&1
  fi
  if [ -d /host-ssh ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    if [ -f /host-ssh/authorized_keys ]; then
      cp /host-ssh/authorized_keys /root/.ssh/authorized_keys
    else
      for pub in /host-ssh/id_*.pub; do
        [ -f "$pub" ] && cat "$pub" >> /root/.ssh/authorized_keys
      done
    fi
    chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
  fi
  mkdir -p /run/sshd
  /usr/sbin/sshd
  echo "sshd started" >&2
fi

# --- stage 1: herdr server. The bridge hard-fails at startup when the daemon socket
# is absent (v0.6.1: startup_daemon_status does a blocking Status call before binding),
# so the SERVER goes first; the bridge still remains a supervised peer for its lifetime.
setsid herdr server "$@" &
SERVER_PID=$!
echo "web: stage 1 — herdr server pid=$SERVER_PID" >&2

# --- stage 2: bridge (optional) ---
start_bridge() {
  [ -x "$BRIDGE_BIN" ] || { echo "web: bridge binary missing at $BRIDGE_BIN" >&2; return 1; }
  [ -f "$WEB_STATIC_DIR/index.html" ] || { echo "web: missing $WEB_STATIC_DIR/index.html" >&2; return 1; }
  mkdir -p "$(dirname "$WEB_LOG")"
  # socket discovery precedence (pinned v0.6.1 bridge/src/session.rs):
  #   explicit --session > HERDR_SOCKET_PATH > default sessions/<name>/herdr.sock
  # The server creates its socket at $HOME/.config/herdr/herdr.sock (default session),
  # so the bridge is pointed at that exact path. No --herdr-socket flag exists.
  setsid env HERDR_SOCKET_PATH="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" \
    "$BRIDGE_BIN" \
      --host "$WEB_BIND" \
      --port "$WEB_PORT" \
      --static-dir "$WEB_STATIC_DIR" \
      ${WEB_ALLOW_HOST:+--allow-host "$WEB_ALLOW_HOST"} \
      >>"$WEB_LOG" 2>&1 &
  BRIDGE_PID=$!
  echo "web: stage 2 — bridge pid=$BRIDGE_PID on :$WEB_PORT (log: $WEB_LOG)" >&2
  # wait for the server socket file to exist before the bridge probes the daemon
  local sock i=0
  sock="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"
  while [ ! -S "$sock" ]; do
    i=$((i + 1))
    if [ "$i" -gt 80 ]; then
      echo "web: timeout — server socket $sock never appeared" >&2
      return 1
    fi
    kill -0 "$SERVER_PID" 2>/dev/null || { echo "web: server died before socket appeared" >&2; return 1; }
    sleep 0.25
  done
  sleep 1   # socket file may appear slightly before the accept loop is live
  i=0
  while ! curl -fsS -o /dev/null "http://127.0.0.1:${WEB_PORT}/" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
      echo "web: timeout — bridge not answering on :$WEB_PORT (see $WEB_LOG)" >&2
      tail -n 30 "$WEB_LOG" >&2 2>/dev/null || true
      return 1
    fi
    kill -0 "$BRIDGE_PID" 2>/dev/null || { echo "web: bridge died during startup" >&2; tail -n 30 "$WEB_LOG" >&2; return 1; }
    sleep 0.5
  done
  echo "web: stage 2 ready — http://127.0.0.1:${WEB_PORT}/" >&2
  return 0
}

if [ "$HERDR_WEB" = "true" ]; then
  start_bridge || { echo "web: bridge stage failed; exiting" >&2; teardown; exit 1; }
fi

trap 'on_signal TERM' TERM
trap 'on_signal INT'  INT
trap 'on_signal HUP'  HUP

wait "$SERVER_PID"
SERVER_RC=$?
echo "web: herdr server exited rc=$SERVER_RC" >&2
teardown
exit "$SERVER_RC"
