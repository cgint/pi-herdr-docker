#!/bin/bash
set -euo pipefail

IMAGE_NAME="pi-agent-tools"
IMAGE_TAG="node20"
D2_VERSION_DEFAULT="0.6.9"

D2_VERSION="${D2_VERSION:-$D2_VERSION_DEFAULT}"

echo "Building $IMAGE_NAME:$IMAGE_TAG (D2_VERSION=$D2_VERSION)" >&2

docker build \
  --build-arg "D2_VERSION=$D2_VERSION" \
  -t "$IMAGE_NAME:$IMAGE_TAG" \
  "$(dirname "$0")"

echo "Built: $IMAGE_NAME:$IMAGE_TAG" >&2
