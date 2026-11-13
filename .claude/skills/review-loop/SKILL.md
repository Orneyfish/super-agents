---
name: review-loop
description: Build one approved feature or ticket to completion in this session with fresh-context builder, tester and reviewer subagents, looping until every eval passes and review finds nothing new. Run after write-eval (or write-tickets plus ready) has been approved. For many tickets in parallel use the superagent command instead.
argument-hint: <feature-name | ticket-number>
disable-model-invocation: true
allowed-tools: Bash(super-agents *)
---

You are the orchestrator for "$ARGUMENTS". You never write feature code, test, or review yourself. Each of those runs in a fresh subagent so none of them inherits your reasoning or each other's: `super-agents:builder`, `super-agents:tester`, `super-agents:reviewer`. Give them paths and findings, not your opinions.

**Harness note.** `super-agents:<role>` names the subagent definitions in `agents/<role>.md`; Claude Code runs them as subagents. In a harness without Claude-style subagents, run each role in a fresh session or context seeded with that file's body, and keep the roles separate: whoever built the code never tests or reviews it. Hooks (the done-gate) are Claude Code only; elsewhere run `super-agents check-evals <dir> --passed` yourself before saying the work is done.

**`<dir>`** is the feature directory: `specs/tickets/NNN-*` if "$ARGUMENTS" is a three-digit ticket number, otherwise `specs/<name>`.

## Preconditions (if any fails, stop and tell the user)
1. `super-agents check-evals <dir> --ready` prints `OK`. If not, the evals are not approved: point to `/super-agents:write-eval` (or `/super-agents:mark-ready`).
2. In a git repo, not on main/master. Switch to `feat/<name>` (`git switch feat/<name>` or `git switch -c feat/<name>`). If the tree has unrelated uncommitted changes, ask what to do with them first.
3. Read `**Risk:**` from `<dir>/RD.md`. Run `super-agents board set <dir or NNN> building`.

## State
Create `.super-agents/state.md` (a Stop hook reads it and refuses "done" while evals are not passing in `results.md`):
```
---
dir: <dir>
session: <this session's id, from "This session's id is ..." in your session context; leave the line out if you were not given one>
active: true
awaiting_user: false
risk: <risk>
round: 0
max_rounds: 5
gate_blocks: 0
base: <git rev-parse HEAD>
checkpoint: <git rev-parse HEAD>
---
| id | class | severity | location | first | last | status |
|----|-------|----------|----------|-------|------|--------|
```

## Each round N (1 to 5)
1. Set `round: N` and `gate_blocks: 0`.
2. **Build.** Spawn `super-agents:builder` with `<dir>`, N, every open finding (id, class, location, text) and every failing eval. Regressions (evals that passed before and fail now) come first. From round 3 on, if anything still fails, start the prompt with `RETHINK:` plus the reviewer's rethink text so the builder changes approach instead of patching.
3. **Test.** Spawn `super-agents:tester` with `<dir>`, the port and a test account (per `review.md`). Write `<dir>/results.md` from its PASS/FAIL lines, copied verbatim (never change a result), in this format:
   ```
   # Results: <dir name>
   **Updated:** <UTC timestamp>
   **Review:** pending
   | eval | result | evidence |
   |------|--------|----------|
   | E1 | pass | evidence/E1-signup.png: welcome banner visible |
   ```
4. **Review.** Spawn `super-agents:reviewer` with `<dir>`, N, risk, `base` and `checkpoint` (the commit SHAs from the state file), and the already-reported findings (id, class, location). Scope: round 1 the whole change vs `base`; round 2+ the diff since `checkpoint`, which is more than the latest fixes when step 6 skipped the checkpoint after a regression (the reviewer is told). It reports each problem with a class label and does not repeat old findings. Update the `**Review:**` line in `results.md` (`clean`, `findings-fixed`, or `open: <n>`).
5. **Record.** Add new findings to the table with ids; update `last` for any marked `STILL-PRESENT`; mark findings fixed when the reviewer no longer sees them.
6. **Checkpoint.** If no previously passing eval regressed, commit: `git add -A && git commit -m "super-agents(<name>): round N, P/T evals pass"`, (`.super-agents/` is git-ignored by `init`), then set `checkpoint:` to the new HEAD; if an eval regressed, commit nothing and leave `checkpoint:` as it is. Committing relies on the project's CLAUDE.md super-agents block; if it is missing, ask once before the first commit. Never push.
7. **Decide, in this order:**
   - **Done**: every eval passes and the reviewer's verdict is `clean` (nothing at or above the risk threshold).
   - **Stuck**: a finding of the same class and location is still open after two rounds of fixes. Stop and show the user the finding; the builder is not converging.
   - **Cap**: N = 5. Stop and report what remains. (5, because each round builds, runs every eval, and then reviews.)
   - Otherwise start round N+1.

Questions you cannot settle (ambiguous or conflicting requirements, the builder's Questions, an eval that contradicts the mockup): set `awaiting_user: true`, give a short progress report (round, evals P/T, open findings), ask, and set it back to `false` once answered. Product decisions are the user's.

## Finish
1. Set `active: false`. On Done run `super-agents board set <dir or NNN> done` and make the final checkpoint commit; if stopping unfinished, leave the status `building`.
2. Report plainly: rounds used, evals P/T with where the evidence lives (`<dir>/results.md`, `<dir>/evidence/`), anything still open (do not hide it), branch name.
3. **Learned rules.** For each finding class that came back in two or more rounds, or any finding the user calls a non-problem, propose a one-line rule for the "Rules learned over time" section of `review.md`. Append only the ones the user approves.
4. For features users will see, suggest `/super-agents:first-time-user <name>` next.
