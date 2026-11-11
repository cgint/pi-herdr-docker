#!/usr/bin/env bash
# Create the spike sandbox: herdr server as canonical main process, two virtiofs mounts,
# policy-spike.yaml, canary provider. Usage: create-sandbox.sh <name> <fixtures-dir>
set -euo pipefail
cd "$(dirname "$0")"; . ./env.sh
NAME="${1:?name}"; FX="${2:?fixtures dir with dev/ and ro/}"
DC=$(printf '{"vm":{"mounts":[{"type":"bind","source":"%s/dev","target":"/hostdev","read_only":false},{"type":"bind","source":"%s/ro","target":"/hostro","read_only":true}]}}' "$FX" "$FX")
openshell sandbox create --name "$NAME" --from pi-herdr-sbx:spike --policy policy-spike.yaml \
  --provider canary --driver-config-json "$DC" --detach --no-tty -- herdr server
