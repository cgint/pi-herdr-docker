# Spike: pi + herdr as a Docker Sandboxes (sbx) template (topology A).
# See docs/docker-sandbox-sbx.md. Base already provides: user agent (uid 1000),
# Node 22, git, rg, jq, curl, python3, sudo.
#
# Build + load:
#   docker build -t pi-herdr-sbx:spike spike/sbx
#   docker image save pi-herdr-sbx:spike -o /tmp/pi-herdr-sbx.tar
#   sbx template load /tmp/pi-herdr-sbx.tar
FROM docker.io/sbx/shell-image:latest

ARG HERDR_VERSION=0.9.2

USER root
SHELL ["/bin/bash", "-c"]

RUN set -euo pipefail; \
  apt-get update; \
  apt-get install -y --no-install-recommends fd-find; \
  ln -sf "$(command -v fdfind)" /usr/local/bin/fd; \
  rm -rf /var/lib/apt/lists/*

RUN set -euo pipefail; \
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN set -euo pipefail; \
  npm install -g @earendil-works/pi-coding-agent@latest; \
  npm cache clean --force

# herdr: checksum-pinned, same resolution as Dockerfile.herdr
RUN set -euo pipefail; \
  case "$(dpkg --print-architecture)" in \
    amd64) asset="linux-x86_64" ;; \
    arm64) asset="linux-aarch64" ;; \
    *) echo "unsupported arch" >&2; exit 1 ;; \
  esac; \
  rel=$(curl -fsSL https://herdr.dev/latest.json | jq -c ".releases[\"${HERDR_VERSION}\"]"); \
  [[ "$rel" != "null" && -n "$rel" ]] || { echo "herdr ${HERDR_VERSION} not in releases map" >&2; exit 1; }; \
  curl -fsSL "$(jq -r ".assets[\"$asset\"]" <<< "$rel")" -o /tmp/herdr; \
  echo "$(jq -r ".sha256[\"$asset\"]" <<< "$rel")  /tmp/herdr" | sha256sum -c -; \
  install -m 0755 /tmp/herdr /usr/local/bin/herdr; \
  rm -f /tmp/herdr; \
  herdr --version

USER agent
