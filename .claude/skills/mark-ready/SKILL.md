---
name: mark-ready
description: Mark reviewed tickets or features as ready to build. Runs only on the user's explicit say-so for named tickets, all draft tickets, or a feature directory.
argument-hint: <NNN ...|all|feature-dir>
disable-model-invocation: true
allowed-tools: Bash(super-agents *)
---

The user running this is the approval step: draft means "written, not yet approved", ready means "approved, may be built". For each target in "$ARGUMENTS" (a three-digit ticket number, `all` = every draft ticket on the board, or a feature directory like `specs/checkout`):

1. `super-agents check-evals <dir>` must print `OK`. If it does not, show the problems and leave that ticket as it is.
2. `super-agents board set <NNN or dir> ready` (this changes the `**Status:**` line in `RD.md` and, for a ticket, its board row).
3. After the last one, `super-agents board check` for tickets.

Report which are now ready. For tickets, say which can run right now and which wait on others (from the Runs column), and that the next step is `superagent` in a terminal. For a single feature, the next step is `/super-agents:review-loop <name>`.
