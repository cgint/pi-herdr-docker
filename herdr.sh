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
# Web UI (additive; same herdr-state volume, browser on http://127.0.0.1:8787):
#   ./herdr.sh up-web         # build + start the web container (bridge + server)
#   ./herdr.sh web-url        # print the browser URL
#   ./herdr.sh web-log        # tail web container logs
#   ./herdr.sh attach-web     # TUI attach inside the web container
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
#   WORKDIR_REPO     repo to mount at /workspace/current-repo (default: $PWD)
#   PROFILE          pi profile (default: minimal)
#   OLLA_BASE_URL    local LLM gateway (default: http://host.docker.internal:40114)
#   OLLA_PROVIDER_NAME provider name for the gateway (default: home-llm)
#   RW_DIRS          colon-separated list of host dirs to mount rw
#                    (overrides the ro ~/dev and ~/dev-external parents)
#                    e.g. RW_DIRS=~/dev/repo-a:~/dev-external/repo-b
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
CW="pi-agent-herdr-web"
VOL="herdr-state"
PORT=2222
if [[ -n "$INST" ]]; then
  C="pi-agent-herdr-$INST"
  VOL="herdr-state-$INST"
  PORT=$((2222 + $(printf '%s' "$INST" | cksum | awk '{print $1 % 200}')))
fi

PROFILE="${PROFILE:-minimal}"
WORKDIR_REPO="${WORKDIR_REPO:-$PWD}"

# --- build volume mount flags ---
build_rw_dir_flags() {
  local flags=()
  if [[ -n "${RW_DIRS:-}" ]]; then
    IFS=':' read -ra dirs <<< "$RW_DIRS"
    for d in "${dirs[@]}"; do
      # expand ~
      d="${d/#\~/$HOME}"
      # mount rw at the same host path inside the container
      flags+=(-v "${d}:${d}")
    done
  fi
  printf '%s\n' "${flags[@]}"
}

docker_up() {
  if docker inspect "$C" >/dev/null 2>&1; then
    echo "$C already running" >&2
    return
  fi
  docker volume create "pi-agent-herdr_${VOL}" >/dev/null 2>&1

  # Build RW_DIRS flags
  local rw_flags=()
  if [[ -n "${RW_DIRS:-}" ]]; then
    IFS=':' read -ra dirs <<< "$RW_DIRS"
    for d in "${dirs[@]}"; do
      d="${d/#\~/$HOME}"
      rw_flags+=(-v "${d}:${d}")
    done
  fi

  docker run -d \
    --name "$C" \
    --init \
    -t \
    -p "${PORT}:22" \
    -v "${HOME}/.pi:/pi" \
    -v "$(pwd)/herdr-config.toml:/opt/herdr-config.toml:ro" \
    -v "pi-agent-herdr_${VOL}:/root/.config/herdr" \
    -v "${HOME}/dev:/Users/cgint/dev:ro" \
    -v "${HOME}/dev-external:/Users/cgint/dev-external:ro" \
    "${rw_flags[@]+"${rw_flags[@]}"}" \
    -v "${WORKDIR_REPO}:/workspace/current-repo" \
    -v "${HOME}/.ssh:/host-ssh:ro" \
    -e "PI_CODING_AGENT_DIR=/pi/profiles/${PROFILE}/agent" \
    -e "UV_CACHE_DIR=/tmp/uv-cache" \
    -e "XDG_CACHE_HOME=/tmp/xdg-cache" \
    -e "XDG_DATA_HOME=/tmp/xdg-data" \
    -e "PATH=/usr/local/bin:/usr/bin:/bin" \
    -e "GEMINI_API_KEY=${GEMINI_API_KEY:-}" \
    -e "OLLA_BASE_URL=${OLLA_BASE_URL:-http://host.docker.internal:40114}" \
    -e "OLLA_PROVIDER_NAME=${OLLA_PROVIDER_NAME:-home-llm}" \
    pi-agent-herdr:node22
  echo "$C started (ssh port ${PORT})" >&2
}

CMD="${1:-up}"
[[ $# -gt 0 ]] && shift

# --- web mode: use docker compose (separate compose file) ---
if [[ "$CMD" == up-web || "$CMD" == web-url || "$CMD" == web-log || "$CMD" == attach-web ]]; then
  case "$CMD" in
    up-web)
      if docker inspect "$CW" >/dev/null 2>&1; then
        echo "$CW already running (compose ps: docker compose -f docker-compose.herdr-web.yml ps)" >&2
      elif docker inspect "$C" >/dev/null 2>&1; then
        echo "$C is running — web mode drives the SAME herdr-state volume; stop it first: $0 down" >&2
        exit 1
      else
        WORKDIR_REPO="$WORKDIR_REPO" PROFILE="$PROFILE" \
          docker compose -f docker-compose.herdr-web.yml up -d --build
      fi
      docker compose -f docker-compose.herdr-web.yml ps
      ;;
    web-url)
      echo "http://127.0.0.1:${WEB_PORT:-8787}/"
      ;;
    web-log)
      docker compose -f docker-compose.herdr-web.yml logs -f herdr-web
      ;;
    attach-web)
      docker compose -f docker-compose.herdr-web.yml exec -it herdr-web herdr
      ;;
  esac
  exit 0
fi

# --- all other commands: use docker run / docker exec ---
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
    echo "usage: $0 [-n <instance>] {up|attach|agent-list|status|stop|down|exec <cmd...>}" >&2
    echo "       $0 {up-web|web-url|web-log|attach-web}" >&2
    exit 1
    ;;
esac
