# Issue #28 implementation guide: tiered routing, run budget, final report

For the Sonnet and Haiku agents who implement it, and for the owner who reviews it. Design only: nothing but this file was written. Baseline: `main` at `924d6b0` (v0.5.0), `bash tests/run.sh` prints `787 passed, 0 failed`, installed CLI `2.1.322 (Claude Code)`.

Words used here. **Tier**: the model and effort a worker runs on. **Router start**: one Agent call made by the router (not the testers and reviewers that workers start). **UNVERIFIED**: not confirmed from this repo or the installed CLI; each one has a command to check it.

## 0. Short version

- Route by **parameters on the Agent call**, not by new agent files. The installed CLI's Agent tool takes a per-call `model` and `effort`. The router keeps starting `super-agents:worker`, so the done-gate, the watchdog and the allowlist keep working unchanged. One live probe (WP0) must confirm the model override is honoured before WP1 lands.
- Decline `senior-worker`, `senior-worker-lite`, `junior`, `clerk` and `reporter`. A new worker type would not be gated (`scripts/worker-gate.sh:10`), and splitting a ticket among juniors breaks the rule that one ticket is one fresh context.
- Budget and final report are router prompt rules, as the issue proposes. They are nudges, not controls, and the docs must say so. A cost limit and a wall-time limit are not feasible for the router.
- No change to `skills/`, `scripts/`, `hooks/`, `core/`, ticket or board formats. Changed files: `agents/router.md`, `agents/worker.md` (and their `.claude/agents` copies), `templates/review.md`, `README.md`, `docs/ARCHITECTURE.md`, `tests/run.sh`.

## 1. What the issue asks for

### 1.1 Requests, what exists, verdict

| # | Request | Exists today | Verdict | Reason |
|---|---|---|---|---|
| 1 | Opus tier for judgement-heavy and high-risk tickets | Every agent below the router is `sonnet` (`agents/*.md` line 5); risk changes eval strictness and the reviewer's threshold only (`skills/classify-risk/SKILL.md:19`) | **Do differently** | Per-call `model` and `effort` on the existing worker (section 2, D1). |
| 2 | Four new agent files (`senior-worker`, `senior-worker-lite`, `junior`, `clerk`) | none | **Decline** | Ungated, duplicates `worker.md`, and nests work inside a ticket (D1, D2). |
| 3 | Haiku tier for mechanical work | none in the plugin (`.claude/agents/watchdog.md` is `haiku`, a project copy only) | **Decline for now** | No ticket is "mechanical": a ticket goes end to end (`skills/write-tickets/SKILL.md:13`). The mechanical role here is the tester, which is the proof; N-08 says no model is changed on belief (`docs/design/2026-11-13-design-issues-and-fixes.md:609`, `:625`). Open question 5. |
| 4 | Routing table in `router.md`, tier shown in the plan | plan shows kind and risk (`agents/router.md:34`) | **Do** | WP1. |
| 5 | Add new types to the router's `Agent(...)` line | 8 types (`agents/router.md:4`) | **Decline** | No new types. |
| 6 | `## Budget` in `review.md`: max workers at once, max agent runs | "There is no budget ceiling" (`README.md:128`) | **Do**, as a prompt rule | WP1, WP3. The router counts only what it starts (D3). |
| 7 | Optional cost limit | none | **Decline** | The router has no tool that shows cost, and `claude --help` says `--max-budget-usd` "only works with --print"; `superagent` is interactive. |
| 8 | Wall-time limit (from the policy) | per-ticket `slow_min` in the watchdog (`agents/watchdog.md:19`) | **Decline** | The router has no clock (no Bash, `router.md:4`). `slow_min` stays the time signal. |
| 9 | Final report | one-line updates (`router.md:51`, `:54`) | **Do**, in chat | WP1. Built from files, before `drop specs` (D4). No dollar figure. |
| 10 | Haiku `reporter` agent writing `.super-agents/report.md` | none | **Decline** | A new agent, allowlist entry, README row and copy for a file the chat already holds. Open question 4. |
| 11 | `## Handoff` block when a worker stops blocked or is restarted | blocked workers write `**Outcome:** blocked` (`agents/worker.md:35`) | **Do differently** | Only a worker that stops on purpose can write it; the router carries it to the replacement, which resumes from the branch (D5). A worker that hung writes nothing. |
| 12 | README: `--permission-mode default` and its trade-off | `README.md:95` already says "pass your own `--permission-mode <mode>` to override"; `scripts/superagent.sh:21` honours it | **Do** (one paragraph) | WP4. What a background worker does at a prompt in that mode is UNVERIFIED (section 1.3). |
| 13 | Web tools for research | workers and testers have none (`worker.md:4`, `tester.md:15` "you have no web tool") | **Not in this change** | Not in the issue's acceptance list; widens what an unattended agent with Bash reads. Open question 6. |
| 14 | Optional opus reviewer for high risk | reviewer is `sonnet`, high (`agents/reviewer.md:5-6`) | **Not in this change** | Open question 7. |
| 15 | Acceptance: `tests/run.sh` checks `junior` and `clerk` have no `Agent` tool | n/a | **Replace** | Replaced by the guards in WP5. |
| 16 | Acceptance: one live run with a high-risk research ticket and a low-risk code ticket | none | **Do** | WP6, by the owner (it costs money). |

### 1.2 Claims in the issue, checked

| Issue claim | Result | Evidence |
|---|---|---|
| "Effort is set per agent file ... each tier needs its own agent file" (conflict 2, question 1) | **Wrong for the installed CLI** | `/opt/claude-code/bin/claude` (2.1.322) contains the Agent tool's parameter texts: "Optional model override for this agent. Takes precedence over the agent definition's model frontmatter and the configured default subagent model." and "Reasoning effort for this agent. Set this ONLY when the user, or instructions such as CLAUDE.md or a skill, explicitly ask that this agent or delegated work run at a specific effort level". Check: `grep -a -c -F "Optional model override for this agent" /opt/claude-code/bin/claude` prints `1`. The enum `"sonnet","opus","haiku"` is in the same binary. The 2026-11-11 runs never passed these keys (`docs/design/evidence/live/run3-router-allowlist/hooklog-summary.txt`: `input_keys=['description', 'prompt', 'run_in_background', 'subagent_type']`), so run-time behaviour is UNVERIFIED: WP0. |
| The router's `Agent(...)` list limits every descendant (conflict 3) | Right | `design-changes.md:292`, appendix B row 8, `router.md:21`. |
| A subagent's own `Agent(...)` list is not enforced; a `tools:` list is (conflict 6) | Right | `design-changes.md:290`, `:293`. |
| Subagents' own Agent calls ran synchronously (conflict 4) | Right as measured | `design-changes.md:155`. Whether several Agent calls in one message of a subagent run at once was not measured. |
| "Nesting was verified to depth 3 only"; question 3 asks whether router, senior, junior, tester was ever run | Already run | `run3-router-allowlist/hooklog-summary.txt`: `probe-router` started `probe-mid`, which started `probe-chain`, which started `probe-leaf` (four agents in a chain, haiku probes). Not needed by this design. |
| A new worker type only needs adding to `router.md` line 4 | **Incomplete** | `scripts/worker-gate.sh:10` is `[ "$at" = super-agents:worker ] \|\| exit 0`: any other type finishes with failing evals and no gate. `tests/run.sh:270` asserts that near-miss names are not gated, and N-03 records the exact match as a user decision. |
| "README says `.claude/agents/general-purpose.md` uses `claude-fable-5-2`" | Wrong file | `README.md` does not mention it. `docs/ARCHITECTURE.md:145-146` does; the file says `model: sonnet`. `ARCHITECTURE.md:148` ("Nothing tests that they stay in sync") is also out of date (`tests/run.sh:607`). Fixed in WP4. |
| "There is no budget", "no final report", "no web tools below the router", `superagent` defaults to auto | Right | `README.md:128`; `router.md:4`, `:51`; `worker.md:4`, `tester.md:4`; `superagent.sh:21`. |
| "This needs no changes to sa-core" | Right for this design | No script or Rust change; a hard budget would need one (open question 2). |

### 1.3 UNVERIFIED, each with a check

| What | Why it matters | Check |
|---|---|---|
| A per-call `model` is honoured for an agent whose definition sets another model | D1 depends on it | WP0 command. Pass: the output names an opus model. |
| A per-call `effort` is honoured | Only cost: if ignored the worker runs at its file's `effort: high` | No cheap observable was found. In the WP6 run, compare the opus worker's cost with the same ticket run without `effort`. |
| The override works when the caller is a `--agent` main thread with a scoped `Agent(...)` list and the target has `isolation: worktree` | The real router case | WP6: the run's transcript shows the Agent call with `model` and the worker's model id. |
| What a background worker does at a permission prompt under `--permission-mode default` (prompt reaches the user, auto-deny, or hang) | README text in WP4 must not promise more than was seen | Run WP6 once with `superagent --permission-mode default` and note what the first worker Bash call does. (`claude --permission-mode default --version` exits 0, so the value is accepted; `--help` lists it as `manual`.) |
| The Read tool can read a file in another worktree | Not relied on: the router relays the handoff (D5) | not needed |

## 2. Design decisions

### D1. Tier is a parameter on the Agent call; the agent type stays `super-agents:worker`

The router passes `model` and `effort` when it starts a worker, from this table (first matching row wins; a missing `**Kind:**` is `code`):

| Ticket | `model` | `effort` |
|---|---|---|
| any kind, risk `high` | `opus` | `medium` |
| `research`, `analysis`, `design` or `plan`, risk `low` or `medium` | `opus` | `low` |
| `code`, `document` or `operations`, risk `low` or `medium` | leave out (the file says sonnet) | leave out (the file says high) |

This is the issue's own table with model and effort in place of agent names. Kind and risk are read from `RD.md` in the main checkout, which the user approved and which is fingerprinted (`.evals.sha256` line 2), so a worker cannot change its own tier.

Rejected: **new agent files per tier** (the issue's proposal 1). Reasons, in order of weight:
1. Not gated. `worker-gate.sh:10` matches one exact name. Gating more names means changing the gate, its tests (`tests/run.sh:269-270`) and a recorded user decision (N-03).
2. Three copies of the worker's 35-line procedure (`worker`, `senior-worker`, `senior-worker-lite`) that differ in two frontmatter lines, each with a `.claude/agents` copy and a README row. C-11 in the issues register is exactly this kind of drift.
3. Every new type must also go on `router.md:4`, where a typo silently stops dispatch (`tests/run.sh:676`).

Fallback if WP0 shows the override is not honoured: section 3, WP1-F.

### D2. One worker per ticket; no juniors inside a ticket; no change to `write-tickets`

Rejected: **a senior that hands building to `junior` and `clerk`** (issue question 2, first option). A ticket is already sized so that "a worker that has read only its own `RD.md` and `evals.md` and the files named in Touches can finish it" (`skills/write-tickets/SKILL.md:14`). Juniors would run one after another (subagent Agent calls were synchronous), in the same worktree, while an opus context waits. `design-changes.md:390` rejected the same shape for the same reason: more agents and re-reading for no added independence, because the tester and reviewer are already separate.

Rejected: **splitting judgement and building into separate tickets** (question 2, second option). `write-tickets/SKILL.md:13` names "all research, then all writing" as "the horizontal split to avoid".

What this conflicts with in the policy: "seniors launch juniors" and "every brief restates the hierarchy" have no place here, because workers launch only a tester and a reviewer. "Each level checks its subordinates" is replaced by the plugin's stronger rule (separate fresh-context tester and reviewer, the gate, the merger's approved-file check, the post-merge checker), as the issue itself asks.

### D3. Budget is a router rule over what the router starts

`review.md` gets a `## Budget` section with two lines. The router reads it on start, shows it in the plan, limits how many workers run at once, counts its own Agent calls, and stops and asks before passing the limit.

Limits, stated plainly so nobody reads it as a control:
- It is a prompt rule on the router. Nothing mechanical refuses the next start.
- It counts **router starts** (worker, teammate, merger, checker, reproducer, watchdog). Testers and reviewers are started by workers; the router never sees them. A solo ticket is 3 router starts and at least 5 agent runs.
- The count lives in the router's context. A restarted router starts at 0 and must say so.
- No cost and no elapsed time (verdict rows 7 and 8).

Why `review.md`: it is committed, the user owns it, the router already reads it for ports (`router.md:23`), and a ticket branch that changes it is refused by the merger (`agents/merger.md:18`, tested as N-01). Rejected: `.super-agents/budget.conf` next to `watchdog.conf` (git-ignored, any agent with Bash can rewrite it).

Rejected for this change: **a hook that counts and denies**. It is feasible: `PreToolUse` fires for the Agent tool on the main thread and in subagents (`run3` hooklog: `PreToolUse ... tool=Agent`), and a hook can deny (`design-changes.md` appendix B row 9). But it needs a counter file with a grammar, a parser for `review.md` in the main checkout, and tests: script or sa-core work the issue excludes. Open question 2.

### D4. The final report is given in chat and built from files

The router has no write tool (`router.md:4`), and that is on purpose (`router.md:9`). It gives the report in chat when the board is finished and whenever it stops early. Two rules keep it honest:
- Results come from files read at report time (`results.md` rows, the `**Review:**` line, `.super-agents/checks/NNN.txt`), not from memory. This is the plugin's "nothing is done without proof" applied to the report.
- The report is given **before** the `drop specs` merger runs, because that step removes `specs/tickets/` from the branch tip (`router.md:51`); afterwards the evidence paths exist only in the branch history, and the report says so.

The agent-start count is the one part that comes from the router's memory; the report must label it as such and say that no cost figure exists.

Rejected: the `reporter` agent (verdict row 10).

### D5. Handoff: the worker writes it when it stops blocked; the router carries it; the replacement resumes from the branch

- A worker that gives up writes a five-line `## Handoff` block into `results.md`, commits, and names its branch.
- The router reads that block from the old worktree (it already reads `results.md` there, `router.md:46`) and puts it, with `resume from branch <branch>`, in the replacement's prompt.
- The replacement is a fresh worker in a fresh worktree. It notes BASE first (so round 1 of the review still covers the whole ticket), then runs `git merge --ff-only <branch>`. That command is verified for a worktree-isolated agent in default and auto mode (`design-changes.md:468`, appendix B row 7).

This also removes the contradiction in `router.md:57` ("a fresh worker that continues in the existing worktree" against `isolation: worktree`) for the case where a handoff exists.

Not solved, and the guide does not pretend to: a worker that hung, crashed or hit `maxTurns` writes no block, and the router cannot learn its branch (no git). Its last heartbeat note and its checkpoint commits are all there is; uncommitted work is lost. That is the rest of C-09 and needs the per-ticket record from `design-changes.md` section (g).

Rejected: the replacement reads the old worktree itself. Whether Read works across worktrees is UNVERIFIED and `git -C <other>` is refused (`design-changes.md:468`).

### D6. What does not change, on purpose

- Approved evals: no new field in `RD.md` or `BOARD.md`, so nothing about approval or fingerprints moves. Rejected: a `**Tier:**` line in `RD.md` (a new field in the template, `check-evals.sh` and two skills, to store what kind and risk already decide).
- Fresh-context verification: tester and reviewer stay separate agents on their own files, whatever the worker's tier.
- Team tickets are not routed; teammates stay as their file says. `design-changes.md` section (f) recommends removing team mode.
- The single-feature `review-loop` is not routed: it has no router.

## 3. Work packages

Order: WP0 first (it decides between WP1 and WP1-F). WP1 to WP5 touch disjoint files and can run in parallel; the exact phrases below are the contract between them, so WP5 can be written before the others land. WP6 last.

| WP | Files | Model | Depends on |
|---|---|---|---|
| WP0 | none (a probe) | owner, or sonnet with the owner's go-ahead (costs a few cents) | - |
| WP1 | `agents/router.md`, `.claude/agents/router.md` | sonnet | WP0 result |
| WP2 | `agents/worker.md`, `.claude/agents/worker.md` | haiku | - |
| WP3 | `templates/review.md` | haiku | - |
| WP4 | `README.md`, `docs/ARCHITECTURE.md` | haiku | - |
| WP5 | `tests/run.sh` | sonnet | phrases from WP1 to WP4 |
| WP6 | none (a live run) | owner | all |

Rules for every package:
- After editing `agents/X.md`, run `cp agents/X.md .claude/agents/X.md`. Both router files are byte-identical today, so a plain copy is right.
- Do not touch frontmatter. Do not write any new `super-agents:<name>` reference (`tests/run.sh:676` fails on a name with no file).
- In `router.md` do not put `Write`, `Edit` or `Monitor` in backticks; in `worker.md` not `SendMessage`, `TaskStop` or `AskUserQuestion` (`tests/run.sh:646` fails when a prompt names a tool its agent lacks).
- `README.md` has an uncommitted edit by the owner (the Codex CLI row). Keep it.
- Acceptance for every package: `bash tests/run.sh` ends with `0 failed`.

### WP0. Probe: is a per-call `model` honoured?

Run in a terminal, outside any project:

```bash
cd "$(mktemp -d)" && git init -q . && claude -p 'Use the Agent tool once: subagent_type "probe", model "opus", effort "low", prompt "say ok". Then reply DONE.' \
  --agents '{"probe":{"description":"probe","prompt":"Reply with the single word ok.","model":"haiku","tools":["Read"]}}' \
  --model haiku --max-budget-usd 0.50 --output-format json | grep -o '"claude-[a-z0-9-]*"' | sort -u
```

- Pass: the list contains an opus model id next to the haiku one (the `modelUsage` part of the result lists every model that ran). Go to WP1.
- **Result, 2026-11-14 (CLI 2.1.322): PASS.** The command ran as written and `modelUsage` listed `claude-haiku-5-5` and `claude-opus-5-5`; cost $0.03. The per-call `model` is honoured for an agent whose file says haiku. `effort` and the real router case are still UNVERIFIED (section 1.3).
- Fail: only haiku ids. Go to WP1-F instead of the routing part of WP1.
- If the command itself errors (the `--agents` flag is in `claude --help`; the `prompt`, `model` and `tools` keys of its JSON were not run), the same question can be put to a session by hand: start `claude --model haiku`, ask it to start any subagent with `model: "opus"`, and read the model shown for that subagent.

### WP1. Router: routing, budget, final report, replacing a worker (sonnet)

All edits in `agents/router.md`. Keep every existing sentence that a test greps for (`at least 5 agent runs each`, `super-agents commit-tickets`, `one queue slot`, `One reproducer at a time`, `watchdog keeps running`, `NOT REPRODUCED`, `drop specs`, `PORT IN USE`, `**Kind:**`, `.super-agents/checks/NNN.txt` twice and once in the Finish paragraph).

1. **New section `## Routing`**, after "Ask before you run":

   > Each solo ticket's worker runs on a tier taken from the `**Kind:**` and `**Risk:**` lines of its `RD.md` in the main checkout (a missing Kind is `code`). First matching row wins:
   >
   > | Ticket | `model` | `effort` |
   > |---|---|---|
   > | any kind, risk `high` | `opus` | `medium` |
   > | `research`, `analysis`, `design` or `plan`, risk `low` or `medium` | `opus` | `low` |
   > | `code`, `document` or `operations`, risk `low` or `medium` | leave out | leave out |
   >
   > Pass `model` and `effort` as parameters of the Agent call that starts the worker; with both left out the worker runs as its file says (sonnet, high). The tier changes nothing else: same agent type, same evals, same tester, reviewer and gates. If the user names a tier for a ticket ("run 003 on sonnet"), use theirs. A replacement worker gets the tier the first one had. Team tickets are not routed.

2. **The plan** (`router.md:34`). Per ticket, show the tier: `NNN title: solo (1 worker, opus/medium)` or `(1 worker, sonnet/high)`. After the existing cost line add a budget line: `budget: S of N router starts used (3 per solo ticket: worker, merger, checker), up to W workers at once`, or `budget: none set in review.md`.

3. **New section `## Budget`**, after Routing:

   > On start, read `## Budget` in `review.md`. `Max workers at once: N`: never have more than N workers and teammates running; start the rest of an approved wave as slots free, without asking again. `Max agent starts: N`: count every Agent call you make (worker, teammate, merger, checker, reproducer, watchdog); a `SendMessage` is not a start. Before a start that would pass N, start nothing more, give the final report so far, and ask the user: raise the limit by a number they give, or stop here. A missing section or line, or the value `none`, means no limit. A value that is neither a whole number nor `none`: ask the user what it should be before you start anything. This is your own count: after a restart it begins at 0, and you say so in the plan. Testers and reviewers that workers start are not in it. You cannot see cost or elapsed time; never report either.

4. **Dispatch** (`router.md:42`, the solo bullet): after "Nothing else: the ticket says the rest." add "The Agent call also carries the tier from Routing." Change "Then start every ticket in the wave at once" to "Then start the wave's tickets, at most `Max workers at once` at a time".

5. **New section `## Final report`**, before "The user":

   > Give it in chat when the board is finished, before you start the `drop specs` merger, and whenever you stop early (the user stops the run, a budget stop, a stuck ticket). Build it from files, not from memory: for each ticket on the board Read `specs/tickets/NNN-*/results.md` in the main checkout (for a ticket not merged yet, in its worktree) and `.super-agents/checks/NNN.txt`.
   >
   > `| ticket | kind, risk | tier | evals | review | check | evidence |`: one row per ticket. Evals is `P/T` counted from the pass rows against the evals in the main checkout's `evals.md`; review is the `**Review:**` line; check is the first line of the checks file, or `not checked`; evidence is the path of `results.md`. A ticket with no results file is `not built`. After `drop specs` these paths are in the branch history, not at its tip: say so.
   >
   > Then four lines. **Agent starts:** per agent type, workers split by tier, against the budget (`12 of 40`); say that it is your own count for this session, that testers and reviewers inside workers are not in it, and that you have no cost figure. **Open decisions:** each with its options and your recommendation first, or `none`. **Blocked or unverified:** every ticket whose check is not `CONFIRMED OK`, with the reason, or `none`. **Next step:** one.
   >
   > Never write a pass, a verdict or a number you did not read from a file or count yourself.

   In the Finish paragraph (`router.md:51`), insert "give the final report, then" before "start `super-agents:merger` once more with the prompt `drop specs`".

6. **Replacing a worker.** In "The watchdog" (`router.md:57`) replace "start a fresh worker that continues in the existing worktree" with "start a replacement (see Replacing a worker)". Add after that section:

   > **Replacing a worker.** A replacement is a fresh worker in a fresh worktree; it cannot continue in the old one. First Read the old worktree's `specs/tickets/NNN-*/results.md` (the worktree path is in the worker's report, or is the folder that holds its `.job/status.json`). If it has a `## Handoff` block, start the replacement with the usual prompt plus `resume from branch <branch>` and the block's lines, copied verbatim. If it has none (the worker hung or ran out of turns), start it with the usual prompt only and tell the user in one line that uncommitted work in the old worktree is not carried over.

   In "On start" step 2, the sentence "ask whether to resume it (message or replace the worker) or restart it" stays; add "A replacement follows Replacing a worker."

**WP1-F (only if WP0 failed).** Keep items 2 to 6. For routing, add `agents/senior-worker.md` and `agents/senior-worker-lite.md` as copies of `worker.md` whose only differences are `name`, `description`, `model: opus` and `effort: medium` / `low`; add both to `router.md:4`; change `scripts/worker-gate.sh:10` to `[[ $at =~ ^super-agents:(worker|senior-worker|senior-worker-lite)$ ]] || exit 0`; add `wg super-agents:senior-worker; has wgate-senior-blocks '"decision": "block"'` next to `tests/run.sh:262` and a guard that the three bodies (everything after the second `---`) are identical; add two README rows (`tests/run.sh:672` fails without them) and the `.claude/agents` copies. The routing table then names agent types instead of parameters. Tell the owner before doing this: it reverses N-03.

### WP2. Worker: handoff and resume (haiku)

Edits in `agents/worker.md`.

1. Step 1 (**Start**, line 15), append:

   > If the prompt says `resume from branch <branch>`: after noting BASE, run `git merge --ff-only <branch>` on its own. If it fails, reply `blocked: cannot resume from <branch>` and build nothing. Otherwise read the handoff lines in the prompt and go on from their `next step` instead of starting over.

2. Last paragraph (line 35), replace the sentence that starts "If you cannot make the evals pass" with:

   > If you cannot make the evals pass, write `results.md` with the failures, `**Outcome:** blocked: <why>` and the handoff block below, commit with plain, separate commands (`git add -A`, then `git commit -m "ticket NNN: blocked"`), run `super-agents job-status blocked "<why>"`, and report it honestly, naming your worktree and branch.
   > ```
   > ## Handoff
   > - branch: <output of `git branch --show-current`>
   > - done: <what works and is committed>
   > - half-done: <what is started and does not work yet>
   > - unfinished files: <paths, or none>
   > - next step: <the first thing a replacement should do>
   > ```

   Keep the final sentence "Do not mark anything passing that did not pass."

The block cannot weaken the gate: `check-evals.sh` reads only `| E<n> |` rows and the `**Review:**` line (`scripts/check-evals.sh:82-93`), a blocked phase is already an escape (`worker-gate.sh:20`), and a blocked ticket is never accepted (`router.md:46`). A replacement rewrites `results.md` whole in its step 7, which drops the block.

### WP3. `templates/review.md`: the budget section (haiku)

Insert before `## Rules learned over time`:

```
## Budget
Read by the router (`superagent`) only. It is the router's own count, not a hard stop. Use `none` for no limit.
- Max workers at once: 4
- Max agent starts: 40
```

Nothing else changes. `scripts/init-project.sh:11` copies the template only when a project has no `review.md`, so existing projects keep theirs and run with no limit until the owner adds the section by hand. The numbers are a starting point, not tuned (open question 3). Rejected: having `setup` patch an existing `review.md` (it is the user's file; `init-project.sh` never edits it).

### WP4. Docs: `README.md` and `docs/ARCHITECTURE.md` (haiku)

`README.md`:
1. **Kinds of work** (after the list, line 79): one sentence. "In a `superagent` run the kind and the risk also pick the worker's tier: `research`, `analysis`, `design` and `plan`, and anything at risk `high`, are built on opus; the rest on sonnet (see The agents)." Do not add this to `templates/kinds.md`: the router does not read that file, every agent that does pays for each line, and a test caps it at 120 lines (`tests/run.sh:687`).
2. **The agents**, `router` row (line 101): add "picks each worker's tier, keeps to the budget in `review.md`, gives a final report".
3. **Models table** (lines 114-126): leave every row as it is; the `worker` row must stay `| \`worker\` | sonnet | high | 200 |` because `tests/run.sh:672` compares it with the file. Add under the table the three-row routing table from D1 with the sentence "The router passes these as `model` and `effort` on the Agent call; the worker's file and its gate are the same on every tier."
4. Line 128: replace "There is no budget ceiling." with a new heading `### Budget` and: "`review.md` may hold a `## Budget` section (`Max workers at once`, `Max agent starts`). The router shows it in its plan, starts at most that many workers at once, counts the agents it starts itself, and stops and asks before passing the limit. It is the router's own count: it does not include the testers and reviewers that workers start, it begins at 0 when the router restarts, and nothing mechanical enforces it. There is no cost limit and no time limit. Projects set up before this version have no section and no limit; add it by hand."
5. New short section after it, `### Final report`: what D4 says, in three sentences, including "no cost figure" and "given before `specs/tickets/` is dropped".
6. **Known limits**, the "Parallel mode runs unattended" bullet (line 160): add "`superagent --permission-mode default` asks before each tool call that needs permission instead: more prompts, fewer unattended hours. How a background worker behaves at such a prompt has not been run live." Replace the last sentence with what WP6 observed, if it was checked.
7. **Ticket folder** (line 140): `results.md` comment gains "a blocked worker adds a `## Handoff` block".

`docs/ARCHITECTURE.md`:
1. Lines 144-148: the copies are byte-identical except the `model:` line of `watchdog.md` (`haiku`); `general-purpose.md` says `model: sonnet`; `tests/run.sh` does test the sync (N-04 guard).
2. Section 1.2 step 4: add that the router passes a tier per ticket and keeps to the budget; step 7: the final report comes before `drop-specs`.
3. Section 2.3, under the harness facts: add the per-call `model` and `effort` parameters, with the binary-string evidence from section 1.2 above and the WP0 result.

### WP5. Guards in `tests/run.sh` (sonnet)

Add one behaviour test after line 94 (it must come before line 96, which rewrites the file):

```bash
# #28: a handoff block in results.md is not a result row: a passing file still passes with one
printf '\n## Handoff\n- branch: b\n- done: d\n' >> $D/results.md; t eval-passed-with-handoff 0 $X/check-evals.sh $D --passed
```

Add a block after line 713, in the existing `gq` style:

```bash
# ---- #28 tiered routing, run budget, final report, handoff: prompt guards (the router is a prompt; a live run is the real test)
gq agents/router.md '## Routing' '| any kind, risk `high` | `opus` | `medium` |' 'Pass `model` and `effort` as parameters' 'Team tickets are not routed'
gq agents/router.md '## Budget' 'Max workers at once' 'Max agent starts' 'means no limit' 'You cannot see cost or elapsed time'
gq agents/router.md '## Final report' 'before you start the `drop specs` merger' 'not from memory' 'no cost figure'
gq agents/router.md 'Replacing a worker' 'resume from branch'; ! grep -q 'continues in the existing worktree' "$R/agents/router.md" && ok || bad "router.md still restarts a worker 'in the existing worktree', which isolation: worktree makes impossible"
gq agents/worker.md '## Handoff' 'git merge --ff-only' 'ticket NNN: blocked' 'unfinished files'
gq templates/review.md '## Budget' 'Max workers at once:' 'Max agent starts:'
gq README.md '### Budget' '### Final report' 'no cost limit' 'Max agent starts'; ! grep -q 'There is no budget ceiling' "$R/README.md" && ok || bad "README still says there is no budget ceiling"
# #28: the done-gate matches one agent type (worker-gate.sh), so a tier is a parameter of the worker, never a second ticket-building agent type
for f in "$R"/agents/*.md; do n=$(basename "$f" .md); [ "$(fm "$n" isolation)" != worktree ] || case $n in worker|reproducer) ;; *) bad "agent $n builds in a worktree but scripts/worker-gate.sh gates only super-agents:worker";; esac; done; ok
grep -qF '[ "$at" = super-agents:worker ]' "$R/scripts/worker-gate.sh" && ok || bad "worker-gate.sh no longer matches super-agents:worker exactly; the routing design (docs/design/2026-11-14-tiered-routing-guide.md) relies on it"
```

If WP1-F was taken, drop the last two guards and add the ones named there. Acceptance: `bash tests/run.sh` ends with `0 failed` and a pass count 12 higher than before (799 from today's 787: the handoff test 1, the `gq` and negative checks 9, the two gate guards 2). These lines were dry-run against a copy of today's files: the five prompt guards fail until WP1 to WP4 land, the isolation guard fails when an `agents/senior.md` with `isolation: worktree` is added, and a passing `results.md` still passes `check-evals --passed` with a handoff block appended. `shellcheck tests/run.sh` is clean (ShellCheck is not installed here: use a pip venv with `shellcheck-py`).

### WP6. Live run (owner)

A fixture project with two approved tickets: `001` kind `research`, risk `high`; `002` kind `code`, risk `low`. Set `Max agent starts: 6` so the stop is reached. In a terminal: `superagent`, then "run 001 and 002". Pass when all of these are seen:
1. The plan shows `opus/medium` for 001, `sonnet/high` for 002, and the budget line.
2. Two workers start with type `super-agents:worker`; 001's runs on an opus model id (shown for the subagent in the session, or in its transcript).
3. Before the seventh start the router stops, gives the report so far and asks.
4. After raising the limit, the run finishes; the final report appears before the `drop specs` merger and its eval counts match `results.md`.
5. A worker that cannot pass (make one eval of a third ticket unsatisfiable) leaves a `## Handoff` block and a `ticket NNN: blocked` commit on its branch.

Record what was seen for the UNVERIFIED rows of section 1.3 in `docs/ARCHITECTURE.md` section 2.3.

## 4. Release and compatibility

- **`.claude` copies.** `.claude/agents/*.md` must be byte-identical to `agents/*.md`, except the `model:` line of `router.md` and `watchdog.md`; `.claude/skills` must equal `skills/` (`tests/run.sh:607-611`). This change touches `router.md` and `worker.md` only: copy both. No skill changes, so `.claude/skills` is untouched.
- **Docs that must move together.** `README.md` (Kinds of work, The agents, models table note, Budget, Final report, Known limits, Ticket folder) and `docs/ARCHITECTURE.md` (1.2, 2.1 copies paragraph, 2.3). `templates/kinds.md` is deliberately not changed.
- **Existing projects.** No migration. Their `review.md` has no `## Budget`, which means no limit, as today. Tickets, boards, fingerprints and `results.md` are unchanged; an approved ticket stays approved. A project picks up routing as soon as the plugin updates: high-risk and judgement tickets start costing opus prices. Say this in the release notes.
- **Accounts without opus.** A start with `model: "opus"` would fail for them (UNVERIFIED how). The user can name a tier per ticket ("run 001 on sonnet"); the release notes should say so.
- **Version.** No `core/` change, but a version bump still needs the sa-core build and checksum steps, because the launcher fetches sa-core by plugin version (`README.md:170`). The three version strings must stay equal (`tests/run.sh`).
- **Not carried by CI.** Every behaviour here is a prompt. `tests/run.sh` only pins the wording; WP6 is the proof.

## 5. Open questions for the owner

1. **Per-call override or one agent file per tier?** (issue question 1) Recommendation: per-call `model` and `effort`, pending WP0. It keeps one gated worker type. Agent files only as the WP1-F fallback.
2. **Should the budget be a hard stop?** Recommendation: not in this change. Ship the router rule, see in WP6 whether the router keeps to it, then decide on a `PreToolUse` hook on the Agent tool that counts starts in `.super-agents/` and denies past the limit. That hook would also count the testers and reviewers the router cannot see.
3. **Budget defaults.** Recommendation: the template ships `4` workers at once and `40` router starts (about 13 solo tickets); existing projects stay unlimited. Both numbers are guesses until a real run.
4. **Final report in chat or in a file?** (issue question 4) Recommendation: chat. If a file is wanted later, the cheaper route is one extra duty for the merger's `drop specs` step, not a new agent.
5. **Where does haiku go?** Recommendation: nowhere yet. The candidates are the tester and the watchdog (N-08 step 5); move them one line at a time after WP6 gives a cost and a pass rate per agent type.
6. **Web tools for research tickets.** Recommendation: a separate change that adds `WebSearch` and `WebFetch` to the worker only. The tester keeps `curl` plus `grep -F`, because a saved file is what makes a quote check repeatable.
7. **Opus reviewer for high-risk tickets.** Recommendation: defer. With D1 the worker could pass `model: "opus"` to its reviewer in one sentence, but the review-loop would then differ from the ticket flow; decide after WP6 shows what a sonnet reviewer misses on opus work.
8. **Row 2 of the routing table** (opus at low effort for low and medium risk judgement kinds). Recommendation: ship it as the issue has it, and compare one such ticket on `sonnet/high` in WP6. It is the one row that rests on belief rather than on a measurement.

Skipped or not checked: WP0 and every live behaviour (nothing was run against a model); the JSON keys in the WP0 command were not run. Risk: if the per-call `model` is ignored at run time, routing silently stays on sonnet, which is why WP0 comes first and WP6 checks the model id.
