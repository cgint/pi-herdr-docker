# Ollama

## Local LLM gateway pointed at the Docker host gateway

**Id:** b6ba47ab-be2c-4b21-9d53-12eeeb7804e7
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commit f39a2c6, open items in NOTES.md
**Revisit when:** the local LLM gateway is verified reachable from the container

The container's local-LLM provider points its base URL at the Docker host gateway address (a `host.docker.internal` hostname with the gateway's port) instead of the host's loopback address.

**Reason:** the gateway runs on the host; inside the container, loopback is the container's own loopback, so the only way to reach a host process is through Docker's host-gateway hostname. The provider name was likewise set to a custom value matching the gateway's configuration.

**Consequence:** this is untested end-to-end (the gateway was down when the change was made, per the open items); the entry records the intended wiring, and the pi-state entry on local LLM reachability records the still-unverified state.

**See:** pi-state.md — 7caa9c5c-21d2-4480-9058-2d973cd21e2b — as of 2026-10-10
