# Pi state

## ~/.pi mounted at a flat path, not per-profile

**Id:** 7093db79-50bd-4eae-b4e9-d8b15ff11aad
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** user requirements, `NOTES.md`
**Revisit when:** pi changes how it resolves profile paths

The container mounts the host's `~/.pi` at a single flat path (currently `/pi`) and points pi at the active profile from there, rather than mounting individual profile subdirectories.

**Reason:** pi's profile directories contain symlinks with relative targets (e.g. a profile's auth file symlinks to a shared location via `../../../agent/...`). Mounting the whole tree at one path keeps those relative links resolving; mounting a profile directory on its own breaks every relative link inside it, because the target directory no longer exists at the relative path.

**Rejected alternative:** mount only the active profile directory. Breaks the internal relative symlinks, so pi would see an incomplete, broken profile.

## Pi extensions resolve their dependencies by walking up the directory tree

**Id:** 3d0f41c1-6e57-4f5c-a82d-9a450cce6782
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** pi changes extension dependency resolution

Pi extensions that live in a profile's extensions or git directories resolve their package imports by walking up the directory tree for a `node_modules` directory.

**Reason:** if the profile root has no `node_modules`, resolution falls through to a globally installed package instead of the version the extension was developed against. On this host the per-extension `node_modules` directories were stale symlinks to homebrew paths that do not exist inside the container, so each extension directory and the profile root needed their own dependency install before pi could load them in the container.

**Consequence:** copying a profile into a container (or a fresh machine) without re-running the per-extension install step produces broken extensions that fail at import time, not at install time.

## Local LLM endpoints are unreachable from the container as configured

**Id:** 7caa9c5c-21d2-4480-9058-2d973cd21e2b
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** verified findings, `NOTES.md`
**Revisit when:** the local LLM gateway is reachable from the container

Model providers that point at loopback addresses on the host (a local LLM gateway, a local inference server) are not reachable from inside the container: the container's own loopback is not the host's.

**Reason:** container networking isolates loopback; reaching a host service requires the Docker host gateway address (`host.docker.internal`) plus the service's host-side port, and the container's model config predates that.

**Consequence:** cloud-based providers work from the container; host-only LLM endpoints do not until the container's model configuration is pointed at the host gateway address. Recorded as an open item, untested with the gateway running.
