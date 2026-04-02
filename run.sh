#!/bin/bash
# Run pi inside the tools image with sane mounts.
#
# Usage:
#   run.sh [--profile partner] [--rw docs --rw openspec --rw .pi] [-- <pi args...>]
#
set -euo pipefail

IMAGE_NAME="pi-agent-tools"
IMAGE_TAG="node20"
PROFILE="partner"

# Bash 3.2 + `set -u`: expanding an empty array can trigger "unbound variable".
# We therefore only expand arrays when they have elements.
DEFAULT_RW_DIRS=("docs" "openspec" ".pi")
RW_DIRS=()
RW_DIRS_EXPLICIT=false

# Parse args
PI_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"; shift 2 ;;
    --rw)
      RW_DIRS_EXPLICIT=true
      RW_DIRS+=("$2"); shift 2 ;;
    --)
      shift; PI_ARGS+=("$@"); break ;;
    *)
      PI_ARGS+=("$1"); shift ;;
  esac
done

# If the user didn't specify any --rw flags, use defaults.
if [[ "$RW_DIRS_EXPLICIT" == false ]]; then
  RW_DIRS=("${DEFAULT_RW_DIRS[@]}")
fi

REPO_ROOT="${REPO_ROOT:-$PWD}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Mount repo RO, then bind-mount selected subdirs RW as "holes".
MOUNTS=(
  --mount "type=bind,src=$REPO_ROOT,dst=/workspace/current-repo,readonly"
)
if ((${#RW_DIRS[@]})); then
  for d in "${RW_DIRS[@]}"; do
    if [[ -e "$REPO_ROOT/$d" ]]; then
      MOUNTS+=(--mount "type=bind,src=$REPO_ROOT/$d,dst=/workspace/current-repo/$d")
    fi
  done
fi

# Mount pi config in a way that preserves your profile auth symlink:
#   /pi/profiles/<profile>/agent/auth.json -> ../../../agent/auth.json
# so we mount ~/.pi/agent at /pi/agent.
PI_AGENT_DIR="$HOME/.pi/agent"
PI_PROFILE_DIR="$HOME/.pi/profiles/$PROFILE/agent"

if [[ ! -d "$PI_PROFILE_DIR" ]]; then
  echo "Profile not found: $PI_PROFILE_DIR" >&2
  exit 1
fi

DOCKER_CMD=(
  docker run --rm -it
  --user "$HOST_UID:$HOST_GID"
  --workdir /workspace/current-repo
  "${MOUNTS[@]}"
  --mount "type=bind,src=$HOME/.local/bin,dst=/tmp/home/.local/bin,readonly"
  --mount "type=bind,src=$HOME/dev,dst=/tmp/home/dev,readonly"
  --mount "type=bind,src=$HOME/dev-external,dst=/tmp/home/dev-external,readonly"
  --mount "type=bind,src=$PI_AGENT_DIR,dst=/pi/agent,readonly"
  --mount "type=bind,src=$PI_PROFILE_DIR,dst=/pi/profiles/$PROFILE/agent"
  -e "PI_CODING_AGENT_DIR=/pi/profiles/$PROFILE/agent"
  -e "UV_CACHE_DIR=/tmp/uv-cache"
  -e "HOME=/tmp/home"
  -e "PATH=/tmp/home/.local/bin:/usr/local/bin:/usr/bin:/bin"
  -e "GEMINI_API_KEY=$GEMINI_API_KEY"
  "$IMAGE_NAME:$IMAGE_TAG"
)

# Bash 3.2 + `set -u` treats empty arrays as "unbound" when expanded.
# Only append PI args if there are any.
if ((${#PI_ARGS[@]})); then
  DOCKER_CMD+=("${PI_ARGS[@]}")
fi

exec "${DOCKER_CMD[@]}"
