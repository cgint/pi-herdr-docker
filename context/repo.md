# Repo

## GitHub slug differs from the local directory name

**Id:** e783b4d6-446a-4c78-9083-a576b00eb6e0
**Type:** constraint
**Status:** active
**Evidence:** inferred
**Source:** commit 3583eb5, AGENTS.md current-state section
**Revisit when:** the repository is renamed, or the local directory is renamed to match

The project's GitHub repository is named `pi-herdr-docker` while the local working directory and original project name are `pi-agent-docker`.

**Reason:** the public repository was created (or transferred) under the `pi-herdr-docker` slug; the local checkout kept its original name. The two names are both in use in the project's own files, and a future agent searching for one by the other will not find it.

**Consequence:** any automation, link, or documentation that derives the repository name from the directory name (or vice versa) gets the wrong answer. Both names are recorded so the mismatch is a known fact instead of a bug to "fix" one way or the other.
