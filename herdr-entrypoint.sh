#!/bin/bash
# herdr-entrypoint.sh — start sshd + herdr server in one container.
#
# The container runs as root with HOME=/root (the default). Herdr's state
# dir is therefore /root/.config/herdr, which lives on a named volume.
# SSH sessions also get HOME=/root, so `herdr --remote` finds the server
# socket without any extra env vars.
#
# sshd runs in the background; herdr server is exec'd in the foreground
# so tini (init: true) forwards signals correctly.
set -euo pipefail

# --- migrate herdr state from /tmp/home (old layout) to /root (new layout) ---
HERDR_STATE=/root/.config/herdr
if [[ -d /tmp/home/.config/herdr && ! -f "$HERDR_STATE/session.json" ]]; then
  mkdir -p "$HERDR_STATE"
  cp -a /tmp/home/.config/herdr/. "$HERDR_STATE/" 2>/dev/null || true
  echo "migrated herdr state from /tmp/home to /root" >&2
fi
mkdir -p "$HERDR_STATE"

# Install the herdr config from the repo (mounted read-only at
# /opt/herdr-config.toml). Only if the volume doesn't already have one.
if [[ -f /opt/herdr-config.toml && ! -f "$HERDR_STATE/config.toml" ]]; then
  cp /opt/herdr-config.toml "$HERDR_STATE/config.toml"
fi

# --- sshd setup ---
if dpkg -l openssh-server >/dev/null 2>&1; then
  if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
    mkdir -p /etc/ssh
    ssh-keygen -A >/dev/null 2>&1
  fi

  # Root login with key only. Local Docker container, not network-exposed.
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

  # Install the host's SSH public keys (bind-mounted read-only at /host-ssh).
  if [[ -d /host-ssh ]]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    if [[ -f /host-ssh/authorized_keys ]]; then
      cp /host-ssh/authorized_keys /root/.ssh/authorized_keys
    else
      : > /root/.ssh/authorized_keys
      for pub in /host-ssh/id_*.pub; do
        [[ -f "$pub" ]] && cat "$pub" >> /root/.ssh/authorized_keys
      done
    fi
    chmod 600 /root/.ssh/authorized_keys
  fi

  mkdir -p /run/sshd
  /usr/sbin/sshd
  echo "sshd started" >&2
fi

# --- herdr server (foreground) ---
exec herdr server "$@"
