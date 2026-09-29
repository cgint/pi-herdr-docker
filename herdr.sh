#!/usr/bin/env bash
# herdr.sh — instant headless herdr container with pi, read-write ~/.pi.
#
# Usage:
#   ./herdr.sh                  # start the server (default repo: $PWD)
#   ./herdr.sh attach           # attach to the TUI from inside the container
#   ./herdr.sh agent-list       # list detected agents via socket API
#   ./herdr.sh status           # herdr status inside the container
#   ./herdr.sh stop             # stop the herdr server inside the container
#   ./herdr.sh down             # stop and remove the container
#   ./herdr.sh exec <cmd...>    # run any command in the container
#
# Herdr session state (session.json, session-history.json) persists in
# ./herdr-state/ via bind mount. Remove that dir to start fresh.
#
# Env:
#   WORKDIR_REPO     repo to mount at /workspace/current-repo (default: $PWD)
#   PROFILE          pi profile to use (default: minimal)
#   OLLA_BASE_URL    local LLM gateway URL (default: http://host.docker.internal:40114)
#
set -euo pipefail
cd "$(dirname "$0")"

C=pi-agent-herdr
PROFILE="${PROFILE:-minimal}"
WORKDIR_REPO="${WORKDIR_REPO:-$PWD}"

# Ensure the herdr-state dir and files exist before docker compose tries
# to bind-mount them (docker will create missing bind-mount sources, but
# we want them as regular files, not dirs).
mkdir -p herdr-state
[[ -f herdr-state/session.json ]] || echo '{}' > herdr-state/session.json
[[ -f herdr-state/session-history.json ]] || echo '[]' > herdr-state/session-history.json

up() {
  if docker inspect "$C" >/dev/null 2>&1; then
    echo "$C already exists (use: docker compose -f docker-compose.herdr.yml ps)" >&2
    return 0
  fi
  WORKDIR_REPO="$WORKDIR_REPO" PROFILE="$PROFILE" \
    docker compose -f docker-compose.herdr.yml up -d --build
}

CMD="${1:-up}"
case "$CMD" in
  up|start)
    up
    docker compose -f docker-compose.herdr.yml ps
    ;;
  attach)
    up
    docker compose -f docker-compose.herdr.yml exec -it herdr herdr
    ;;
  agent-list)
    up
    docker compose -f docker-compose.herdr.yml exec herdr herdr agent list
    ;;
  status)
    up
    docker compose -f docker-compose.herdr.yml exec herdr herdr status
    ;;
  stop)
    up
    docker compose -f docker-compose.herdr.yml exec herdr herdr server stop
    ;;
  down)
    docker compose -f docker-compose.herdr.yml down
    ;;
  exec)
    up
    shift
    docker compose -f docker-compose.herdr.yml exec herdr "$@"
    ;;
  *)
    echo "usage: $0 {up|start|attach|agent-list|status|stop|down|exec <cmd...>}" >&2
    exit 1
    ;;
esac
