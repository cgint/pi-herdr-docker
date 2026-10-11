# Multi-instance

## Each herdr instance gets its own volume and SSH port

**Id:** 0c051adb-cd6c-451a-b709-81037ff46992
**Type:** decision
**Status:** active
**Evidence:** inferred
**Source:** herdr.sh, multi-instance section
**Revisit when:** instances need to share state, or the port scheme changes

Running multiple herdr containers in parallel (one per repository, for parallel agent work) gives each instance its own state volume and its own host SSH port, derived deterministically from the instance name.

**Reason:** herdr's state directory contains sockets and a single coherent session; two containers cannot share one state volume. A deterministic per-name port (base port plus a hash of the name) keeps multi-instance usage from requiring the user to track which port is which.

**Rejected alternative:** one shared state volume for all instances. Herdr's server would see another instance's sockets and session state, and concurrent writes would corrupt it; each instance needs its own volume.

**Rejected alternative:** let the user assign ports manually. Works for two instances; breaks down as the number grows, since there is no way to remember which port belongs to which instance.
