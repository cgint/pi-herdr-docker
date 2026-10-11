# Dockerfile

## Herdr binary pinned by version and checksum in the image

**Id:** d825282b-ff1a-4f18-8c34-ea8896f31b1b
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** Dockerfile.herdr
**Revisit when:** herdr is installed by a different mechanism

The herdr binary is downloaded into the image at a pinned version with a SHA256 checksum verified at build time.

**Reason:** herdr is the state-owning component of the whole workflow; an unpinned or unverified binary would make the state format (and therefore state persistence across container rebuilds) depend on whatever the upstream server happened to serve at build time.

**Rejected alternative:** install herdr from an unpinned release URL. A herdr release that changes state format would silently break state carried in the named volume from an earlier build.

## herdr-web source vendored as a pinned tarball, not fetched at build time

**Id:** c77546b5-1354-4f19-a6ec-6f877ca9ae56
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commit 8a3385f, build-context directory
**Revisit when:** the herdr-web bridge is moved to a versioned release

The web-UI bridge image builds from a source tarball checked into `build-context/`, with the archive's SHA256 pinned, rather than fetching herdr-web's source from its upstream at build time.

**Reason:** the bridge's source is not a versioned release the project can point at by tag; pinning a specific commit as a checksummed archive makes the build reproducible without depending on upstream's default branch staying compatible. The archive is MIT-licensed upstream, matching this project's license.

**Rejected alternative:** clone or fetch the upstream repository at image build time. The build would silently track upstream's default branch; a breaking change upstream would break the bridge image without any change in this repository.
