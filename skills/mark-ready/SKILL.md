---
name: mark-ready
description: Mark reviewed tickets or features as ready to build. Runs only on the user's explicit say-so for named tickets, all draft tickets, or a feature directory.
argument-hint: <NNN ...|all|feature-dir>
disable-model-invocation: true
allowed-tools: Bash(super-agents *)
---

The user running this is the approval step: draft means "written, not yet approved", ready means "approved, may be built". With `all` and no draft ticket on the board, say there is nothing to mark and stop. For each target in "$ARGUMENTS" (a three-digit ticket number, `all` = every draft ticket on the board, or a feature directory like `specs/checkout`):

1. `super-agents check-evals <dir>` must print `OK` (for a ticket number, `<dir>` is `specs/tickets/NNN-*`). If it does not, show the problems and leave that ticket as it is.
2. `super-agents board set <NNN or dir> ready` (this changes the `**Status:**` line in `RD.md` and, for a ticket, its board row, and fingerprints `evals.md` and `RD.md` as approved). A target that is already `ready`, `building` or `done` keeps the fingerprint of its first approval, so an edit made since is not approved by this step alone: when the user has said they approve the changed files, run `super-agents board set <NNN or dir> draft` first. If `board set` fails (for example `no such ticket or directory: 007`), show its message, leave that target as it is and go on to the next; never edit a `**Status:**` line or `BOARD.md` by hand.
3. After the last one, `super-agents board check` for tickets.

Report which are now ready. For tickets, say which can run right now and which wait on others (from the Runs column), and that the next step is `superagent` in a terminal. For a single feature, the next step is `/super-agents:review-loop <name>`.
