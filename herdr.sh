#!/usr/bin/env bash
# herdr.sh — headless herdr container with pi, read-write ~/.pi.
#
# Single instance (default):
#   ./herdr.sh                # up
#   ./herdr.sh attach         # TUI
#   ./herdr.sh status         # herdr status
#   ./herdr.sh agent-list     # list agents
#   ./herdr.sh down           # stop + remove
#   ./herdr.sh exec <cmd>     # run command in container
#
# Multi-instance (N containers, each with own state + SSH port):
#   ./herdr.sh -n alpha up
#   ./herdr.sh -n alpha attach
#   ./herdr.sh -n beta up
#   docker ps --filter name=pi-agent-herdr    # list all instances
#
# Each instance gets:
#   container:  pi-agent-herdr[-<name>]
#   volume:     pi-agent-herdr_herdr-state[-<name>]
#   ssh port:   2222 (default) / 2223+ (auto-assigned per name)
#
# Env:
#   WORKDIR_REPO     repo to mount (default: $PWD)
#   PROFILE          pi profile (default: minimal)
#   OLLA_BASE_URL    local LLM gateway (default: http://host.docker.internal:40114)
#
set -euo pipefail
cd "$(dirname "$0")"

# --- parse -n flag ---
INST=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) INST="$2"; shift 2 ;;
    -n*) INST="${1#-n}"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"

C="pi-agent-herdr"
VOL="herdr-state"
PORT=2222
if [[ -n "$INST" ]]; then
  C="pi-agent-herdr-$INST"
  VOL="herdr-state-$INST"
  PORT=$((2222 + $(printf '%s' "$INST" | cksum | awk '{print $1 % 200}')))
fi

PROFILE="${PROFILE:-minimal}"
WORKDIR_REPO="${WORKDIR_REPO:-$PWD}"

# --- single instance: use docker compose ---
if [[ -z "$INST" ]]; then
  CMD="${1:-up}"; [[ $# -gt 0 ]] && shift
  case "$CMD" in
    up|start)
      if docker inspect "$C" >/dev/null 2>&1; then
        echo "$C already running" >&2
      else
        WORKDIR_REPO="$WORKDIR_REPO" PROFILE="$PROFILE" \
          docker compose -f docker-compose.herdr.yml up -d --build
      fi
      docker compose -f docker-compose.herdr.yml ps
      ;;
    attach)
      docker compose -f docker-compose.herdr.yml exec -it herdr herdr
      ;;
    agent-list)
      docker compose -f docker-compose.herdr.yml exec herdr herdr agent list
      ;;
    status)
      docker compose -f docker-compose.herdr.yml exec herdr herdr status
      ;;
    stop)
      docker compose -f docker-compose.herdr.yml exec herdr herdr server stop
      ;;
    down)
      docker compose -f docker-compose.herdr.yml down
      ;;
    exec)
      docker compose -f docker-compose.herdr.yml exec herdr "$@"
      ;;
    *)
      echo "usage: $0 {up|attach|agent-list|status|stop|down|exec <cmd...>}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# --- multi-instance: use docker run directly ---
docker_vol_create() {
  docker volume create "pi-agent-herdr_${VOL}" >/dev/null
}

docker_up() {
  if docker inspect "$C" >/dev/null 2>&1; then
    echo "$C already running" >&2
    return
  fi
  docker_vol_create
  docker run -d \
    --name "$C" \
    --init \
    -t \
    -p "${PORT}:22" \
    -v "${HOME}/.pi:/pi" \
    -v "$(pwd)/herdr-config.toml:/opt/herdr-config.toml:ro" \
    -v "pi-agent-herdr_${VOL}:/root/.config/herdr" \
    -v "${WORKDIR_REPO}:/workspace/current-repo" \
    -v "${HOME}/.ssh:/host-ssh:ro" \
    -e "PI_CODING_AGENT_DIR=/pi/profiles/${PROFILE}/agent" \
    -e "UV_CACHE_DIR=/tmp/uv-cache" \
    -e "XDG_CACHE_HOME=/tmp/xdg-cache" \
    -e "XDG_DATA_HOME=/tmp/xdg-data" \
    -e "PATH=/usr/local/bin:/usr/bin:/bin" \
    -e "GEMINI_API_KEY=${GEMINI_API_KEY:-}" \
    -e "OLLA_BASE_URL=${OLLA_BASE_URL:-http://host.docker.internal:40114}" \
    pi-agent-herdr:node22
  echo "$C started (ssh port ${PORT})" >&2
}

CMD="${1:-up}"
[[ $# -gt 0 ]] && shift
case "$CMD" in
  up|start)
    docker_up
    docker ps --filter "name=$C" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ;;
  attach)
    docker_up
    docker exec -it "$C" herdr
    ;;
  agent-list)
    docker_up
    docker exec "$C" herdr agent list
    ;;
  status)
    docker_up
    docker exec "$C" herdr status
    ;;
  stop)
    docker_up
    docker exec "$C" herdr server stop
    ;;
  down)
    docker rm -f "$C" 2>/dev/null || true
    ;;
  exec)
    docker_up
    docker exec "$C" "$@"
    ;;
  *)
    echo "usage: $0 -n <instance> {up|attach|agent-list|status|stop|down|exec <cmd...>}" >&2
    exit 1
    ;;
esac
