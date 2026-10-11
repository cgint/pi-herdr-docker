# Cache

## Cache directories redirected to /tmp, not the mounted host paths

**Id:** 33552e3f-5620-4184-8ce6-e28eca63567b
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commits bef4d72, a645364; run.sh environment variables
**Revisit when:** cache persistence across container restarts becomes a requirement

The container redirects package-manager and other tool cache directories (an uv cache, XDG cache and data directories) to `/tmp` inside the container instead of letting them land in mounted host paths.

**Reason:** caches grow without bound and are cheap to rebuild; persisting them on the host would fill host disk with per-container cache files and create host-owned files (the root-owned-file problem the user-switch plan addresses). Keeping them in the container's own writable layer means they die with the container, which is the correct lifetime for a cache.

**Rejected alternative:** let caches write into mounted host directories. Host disk fills with stale cache files, and the files are root-owned until the user switch lands.
