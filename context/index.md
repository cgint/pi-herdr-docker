# Context index

## 0

## 1

## 2

## 3

## 4

## 5

## 6

## 7

## 8

## 9

## A

## B

## C

- [cache.md](cache.md) — why caches stay in /tmp instead of mounted host paths
- [container-runtime.md](container-runtime.md) — base image choice; the open root-vs-named-user switch

## D

- [dockerfile.md](dockerfile.md) — why herdr and herdr-web are pinned/vendored in the image

## E

- [entrypoint.md](entrypoint.md) — why the entrypoint removes stale herdr sockets at start

## F

## G

## H

- [herdr-cli.md](herdr-cli.md) — herdr agent prompt: why no --until for normal work
- [herdr-state.md](herdr-state.md) — why herdr state is a named volume, config handling, shutdown path, history secrets
- [host-platform.md](host-platform.md) — why macOS Docker Desktop's filesystem limits drive the volume/mount design

## I

## J

## K

## L

## M

- [memory.md](memory.md) — why durable pairing memory lives in committed files by type
- [mounts.md](mounts.md) — why dev dirs are read-only by default, with explicit rw overrides
- [multi-instance.md](multi-instance.md) — why parallel instances each get their own volume and port

## N

## O

- [ollama.md](ollama.md) — why the local LLM gateway is wired through the Docker host gateway

## P

- [pi-in-docker.md](pi-in-docker.md) — which pi package the image installs; why the version is not pinned
- [pi-state.md](pi-state.md) — how ~/.pi is mounted; extension resolution; local LLM reachability

## Q

## R

- [repo.md](repo.md) — why the GitHub slug and the local directory name differ

## S

- [secrets.md](secrets.md) — why API keys are passed per-invocation, not baked in

## T

## U

## V

## W

- [web-ui.md](web-ui.md) — why the web bridge is additive over the server image and shares its state

## X

## Y

## Z
