---
name: review-loop
description: Build one approved piece of work or ticket to completion in this session with fresh-context builder, tester and reviewer subagents, looping until every eval passes and review finds nothing new. Run after write-eval (or write-tickets plus ready) has been approved. For many tickets in parallel use the superagent command instead.
argument-hint: <feature-name | ticket-number>
disable-model-invocation: true
allowed-tools: Bash(super-agents *)
---

You are the orchestrator for "$ARGUMENTS". You never write the work, test, or review yourself. Each of those runs in a fresh subagent so none of them inherits your reasoning or each other's: `super-agents:builder`, `super-agents:tester`, `super-agents:reviewer`. Give them paths and findings, not your opinions. Start each one in the foreground (`run_in_background: false`) and wait for its reply: your turn ending while one still runs is not "done", and the Stop hook only tolerates it, it does not check anything then.

**Harness note.** `super-agents:<role>` names the subagent definitions in `agents/<role>.md`; Claude Code runs them as subagents. In a harness without Claude-style subagents, run each role in a fresh session or context seeded with that file's body, and keep the roles separate: whoever built the work never tests or reviews it. Hooks (the done-gate) are Claude Code only; elsewhere run `super-agents check-evals <dir> --passed` yourself before saying the work is done.

**`<dir>`** is the work directory: `specs/tickets/NNN-*` if "$ARGUMENTS" is a three-digit ticket number, otherwise `specs/<name>`.

## Preconditions (if any fails, stop and tell the user)
1. `super-agents check-evals <dir> --ready` prints `OK`. If not, the evals are not approved: point to `/super-agents:write-eval` (or `/super-agents:mark-ready`).
2. `review.md` exists in the project. If not, stop and tell the user to run `/super-agents:setup-project`.
3. In a git repo, not on main/master. Switch to `feat/<name>` (`git switch feat/<name>` or `git switch -c feat/<name>`). If the tree has unrelated uncommitted changes, ask what to do with them first.
4. Read `**Risk:**` from `<dir>/RD.md`. Run `super-agents board set <dir or NNN> building`.

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
3. **Test.** Spawn `super-agents:tester` with `<dir>` and, when the work has a running app, the port and a test account (per `review.md`). Write `<dir>/results.md` from its PASS/FAIL lines, copied verbatim (never change a result), in this format:
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
1. On Done run `super-agents board set <dir or NNN> done` first: it checks the evals itself and refuses (exit 1, `FAIL` lines) while any is unmet. If it refuses you are not done: go on with the loop or stop unfinished, and never edit `results.md` to get past it. Then set `active: false` and make the final checkpoint commit. If stopping unfinished, set `active: false` and leave the status `building`.
2. Report plainly: rounds used, evals P/T with where the evidence lives (`<dir>/results.md`, `<dir>/evidence/`), anything still open (do not hide it), branch name.
3. **Learned rules.** For each finding class that came back in two or more rounds, or any finding the user calls a non-problem, propose a rule for the "Rules learned over time" section of `review.md`. When the class is mechanical, propose a deterministic check (a command to add to the checks in `review.md`) instead of a prose rule. Append only the ones the user approves.
4. When the work has a live app that users will see, suggest `/super-agents:first-time-user <name>` next.
