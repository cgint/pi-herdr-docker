# Secrets

## API keys are conditionally passed into the container, not baked into the image

**Id:** 85f2c239-b3ff-40b5-b7fd-7027e086d5a3
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** commit a645364
**Revisit when:** the container's credential-handling approach changes

An API key (for a cloud model provider) is passed into the container as an environment variable only when it is set on the host, so the image itself contains no secrets and the container runs with none when the host has none.

**Reason:** baking a key into the image or a committed file would put a live credential in the repository's history or the image registry; passing it per-invocation keeps the image reusable and the credential out of anything that is committed or pushed.

**Rejected alternative:** store the key in a mounted file inside the image build. The key would be in the image layers, readable by anyone who can pull the image, and would have to be rebuilt on every rotation.

**Rejected alternative:** always pass a key (even an empty one). The conditional form makes "no key set" and "key set" visibly different in the container's environment, which matters for debugging which providers are actually reachable.
