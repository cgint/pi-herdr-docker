# pi-agent-docker: a reproducible environment to run pi with common CLI tools.
#
# Includes:
# - pi-coding-agent (npm global)
# - ripgrep (rg)
# - fd
# - uv + uvx
# - d2
# - git, jq, curl, ca-certs
#
# Designed to be used with a host-side wrapper that bind-mounts:
# - repo read-only, with a few writable "holes"
# - PI_CODING_AGENT_DIR (profile) and ~/.pi/agent (for auth symlink targets)

FROM node:20-bullseye

SHELL ["/bin/bash", "-lc"]

# Versions can be overridden at build time.
ARG D2_VERSION=0.6.9

# Basic utilities
RUN set -euo pipefail; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    unzip \
    xz-utils \
    ripgrep \
    fd-find \
    graphviz \
    python3 \
    python3-venv \
    python-is-python3; \
  rm -rf /var/lib/apt/lists/*

# Provide `fd` (Debian calls it `fdfind`)
RUN set -euo pipefail; \
  if command -v fdfind >/dev/null 2>&1; then ln -sf "$(command -v fdfind)" /usr/local/bin/fd; fi

# Install uv/uvx
# Using the official install script (downloads a static binary); move to /usr/local/bin.
RUN set -euo pipefail; \
  curl -LsSf https://astral.sh/uv/install.sh | sh; \
  mv /root/.local/bin/uv /usr/local/bin/uv; \
  mv /root/.local/bin/uvx /usr/local/bin/uvx

# Install d2
# Download the correct archive based on architecture.
RUN set -euo pipefail; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) d2_arch="linux-amd64" ;; \
    arm64) d2_arch="linux-arm64" ;; \
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fL "https://github.com/terrastruct/d2/releases/download/v${D2_VERSION}/d2-v${D2_VERSION}-${d2_arch}.tar.gz" -o /tmp/d2.tgz; \
  tar -xzf /tmp/d2.tgz -C /tmp; \
  install -m 0755 "/tmp/d2-v${D2_VERSION}/bin/d2" /usr/local/bin/d2; \
  rm -rf /tmp/d2.tgz "/tmp/d2-v${D2_VERSION}"

# Install pi (coding agent)
RUN set -euo pipefail; \
  npm install -g @mariozechner/pi-coding-agent @fission-ai/openspec@latest @google/gemini-cli; \
  npm cache clean --force

ENV PATH="/usr/local/bin:$PATH"

# Provide a writable HOME for arbitrary --user uid:gid
RUN set -euo pipefail; mkdir -p /tmp/home; chmod 0777 /tmp/home

# Default to pi
ENTRYPOINT ["pi"]
