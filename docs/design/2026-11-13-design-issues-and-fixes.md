# super-agents: design issues and fixes

Written 2026-11-13 against branch `docs/architecture-and-design-issues` (plugin 0.3.1). Paths are
relative to the repository root. Design only: nothing in the repository was changed.

Companions, which this register references instead of repeating:

- **Review** = `docs/design/2026-11-11-design-review.md` (findings P1 to P9).
- **Roadmap** = `docs/design/2026-11-11-design-changes.md` (target design sections a to h, releases
  v0.4.1 / v0.5.0 / v0.6.0, live-test appendix).
- `docs/ARCHITECTURE.md` describes how the system works today.

## How to read this

- **C-nn** issues are carried over from the review. They are all still open: the code the review
  cited is byte-identical on this branch (`git diff c3810c1 HEAD` outside `docs/` and `.claude/`
  shows only the version strings and the `model:` line of `agents/builder.md` and
  `agents/reviewer.md`). For these the detailed fix is the roadmap's; this register gives the
  pointer, a one-paragraph summary and the verification command.
- **N-nn** issues are new: not in the review, or only touched in passing.
- "Probed" means the real scripts were run against a scratch repository for this document; the
  output is quoted. "Read" means the claim comes from reading the cited lines only.
- Severity: **high** = a ticket or feature can be marked done wrongly, or code runs without the
  user's consent; **medium** = a run stalls, costs much more, or a control is weaker than
  documented; **low** = friction, drift or portability.
- Effort: S = under a day, M = a few days, L = a week or more.
- Threat model: as in the roadmap (`design-changes.md:8`). The system defends against a lazy,
  confused or prompt-injected agent and hostile repository content, not against an agent that
  forges files on purpose with Bash.

Test baseline for this document: `CARGO_NET_OFFLINE=true bash tests/run.sh` gave
`500 passed, 0 failed`; `cargo test --locked` in `core/` gave 43 passed, 0 failed.

---

## Part 1. Carried over from the review (all open)

### C-01 Shell arithmetic runs repository content in both gates

- **Status: fixed.** Counters accept only `^[0-9]{1,3}$` (`eval-gate.sh`, `worker-gate.sh`); a tracked or symlinked `state.md` / `.job/status.json` is ignored with a fixed notice; `session-start.sh` applies the `dir` and `round` grammar; `job-status --name` has a grammar. Tests: `gate-arith-injection`, `gate-tracked-state-ignored`, `gate-symlink-state-ignored`, `worker-gate-arith-injection`, `job-name-grammar`, `session-hostile-dir`. Not done from roadmap (a): the `note`, `ignore` and `app_url` grammars and the `realpath under specs/` rule for `dir`.

- **Severity:** high. **Effort:** S. **Roadmap:** section (a); v0.4.1 item 1.
- **Evidence:** `scripts/eval-gate.sh:24-28` (`$((n+1))` on `gate_blocks` from `state.md`);
  `scripts/worker-gate.sh:15-17` (same on `.job/gate_blocks`); `scripts/session-start.sh:15`
  (unvalidated `dir:` and `round:` text into every session's context). Review P1; reproduced in
  `docs/design/evidence/A-repro.out` (A1, A1b, A2, A9a).
- **How it fails:** a cloned repository tracks `.super-agents/state.md` with `active: true` and
  `gate_blocks: x[$(cmd)]`. The first turn that ends in that clone runs `cmd` with no prompt.
- **Root cause:** values from files an agent or a repository can write are used as shell
  arithmetic and as prompt text without a grammar.
- **Fix:** roadmap (a): accept only `^[0-9]{1,3}$`; ignore a runtime file that is git-tracked or a
  symlink; reuse the `dir` grammar in `session-start.sh`. Rejected there: quoting the arithmetic
  only (still evaluates), blocking when the file is tracked (lets a repo wedge sessions).
- **Verify:** lift A1, A1b, A2 from `docs/design/evidence/A-repro.sh` into `tests/run.sh` with the
  verdict inverted (`gate-arith-injection`: the marker file must not exist and the gate still blocks).

### C-02 The transition to `done` is not gated, and the gated agent owns every release

- **Status: partially fixed.** First steps, backward compatible: (1) `super-agents board set <X> done` runs `check-evals --passed` itself and refuses with the `FAIL` lines, so `done` is gated on the status change whatever `state.md` says (`done-path-is-gated`; the check is in `bin/super-agents`, so `sa-core board set` called directly skips it until `verify` is ported); the review-loop runs it before setting `active: false`, and the merger reports a refusal. (2) The fingerprint is written when a draft is approved or when none exists, not on a later `ready` (`core/src/board.rs`; `fingerprint-not-rewritten`, `core/tests/board_set.rs`); re-approval goes through `draft`, which `mark-ready` now says. Remains: the edge table (any status is still reachable from any other except as above), `loop` and `job` subcommands replacing hand edits of `state.md`, the self-service releases (`awaiting_user`, the block counters, `blocked`), the transition log, and `draft` then `ready` by an agent, which still re-approves (roadmap rule 6).

- **Severity:** high. **Effort:** M. **Roadmap:** section (b); v0.5.0 steps 3 and 5.
- **Evidence:** `skills/review-loop/SKILL.md:63` sets `active: false` first, and
  `scripts/eval-gate.sh:13` exits when `active` is not `true`. `core/src/board.rs:243-246` accepts
  any status from any status; `:274-278` re-fingerprints on every `ready`. Self-service releases:
  `eval-gate.sh:14` (`awaiting_user`), `SKILL.md:40` (resets `gate_blocks`),
  `worker-gate.sh:13,15-17`. Review P2; A3, A4, A5b in `A-repro.out`.
- **How it fails:** an orchestrator with two failing evals sets `active: false` and runs
  `board set <dir> done`; no hook evaluates anything. Or: an agent edits `evals.md`, runs
  `board set <dir> ready`, and the fingerprint now matches the edited file.
- **Root cause:** the check sits on "turn ended" (a hook) instead of on the status change.
- **Fix:** roadmap (b): `done` only through a command that runs the verification itself; the
  fingerprint is written on exactly one edge (draft to ready); `loop` and `job` subcommands replace
  hand edits of `state.md`. Rejected there: moving `active: false` later (the agent still owns the
  flag); removing the 3-block cap (wedges sessions).
- **Verify:** new `tests/run.sh` case `done-path-is-gated`: failing evals plus
  `super-agents loop finish <dir>` exits 1 and the status stays `building`.

### C-03 Evidence is not bound to the code that lands; builders certify themselves

- **Status: partially fixed.** First steps in `scripts/check-evals.sh --passed`: a second row for the same eval is rejected (`duplicate-row-rejected`; the first row used to win), and a `**Review:**` line, when present, must say `clean` or `findings-fixed` (`review-pending-rejected`; the line was read by no script). `agents/worker.md` re-runs every eval after the last fix instead of "the failing evals and their neighbours". Remains, all of roadmap (c): results are still a table the gated agent writes, not a record tied to a tree id and written by the tester; a `results.md` without a Review line still passes; `findings-fixed` is still undefined; the tester reuses whatever answers on its port; the merger runs lint and build only, not the evals on the merged tree.

- **Severity:** high. **Effort:** L. **Roadmap:** section (c); v0.5.0 steps 4 and 7.
- **Evidence:** `scripts/check-evals.sh:59-66` accepts a `pass` cell and any non-empty file.
  `results.md` is written by the gated party (`agents/worker.md:21`, `SKILL.md:42`). Partial
  re-test after fixes (`worker.md:20`). `findings-fixed` is accepted and undefined
  (`agents/router.md:46`). The tester reuses whatever answers on the port (`agents/tester.md:13`).
  The merger runs lint and build only (`agents/merger.md:17`). Review P3.
- **Additional detail found for this document (probed):** `check-evals.sh:60` takes the **first**
  row for an eval id (`head -1`). A `results.md` with `| E1 | pass | evidence/E1.txt |` followed by
  `| E1 | fail | later run |` gives `OK` and exit 0. The `**Review:**` and `**Outcome:**` lines are
  never read by any script (no match for them in `scripts/` or `core/src/`).
- **How it fails:** a worker fixes a review finding, breaks E3, re-tests only E5 "and its
  neighbours", and the old E3 pass row with its old screenshot still satisfies the gate, the router
  and the merger.
- **Root cause:** a pass is a table cell, not a record tied to a tree and written by the tester.
- **Fix:** roadmap (c): tree id, `super-agents result` written by the tester only, `verdict` by the
  reviewer, `verify --passed`, tester run on the merged tree before the merge commit. Add to that
  design: the results record must reject a second row for the same eval within one run.
- **Verify:** roadmap tests `stale-tree-rejected`, `swapped-evidence-rejected`,
  `review-verdict-required`; plus a `duplicate-row-rejected` case.

### C-04 Gates fail open and trust inputs the gated agent wrote

- **Status: partially fixed.** Done (v0.4.1 items 4-6 in part): the worker gate finds the ticket folder by ticket number in the worker's own worktree and no longer reads `dir` (`worker-gate-foreign-dir`); every hook reports hook JSON that does not parse, and the first-time-user's call is then denied (`gate-bad-json-says-so`, `ftu-bad-json-denied`); the launcher checks the cached binary against the checksum on every run (`native-cache-tampered`); the eval gate says in a `systemMessage`, not on stderr, that it cannot run. Remains: the launcher's version check and local-build rule (`native-version-mismatch`, `native-stale-local-build`: they need an `--expect-version` flag in sa-core); with sa-core missing every hook still allows everything, the first-time-user block included, because `tests/run.sh` ("a hook never blocks because sa-core is missing") and `README.md:10` assert exactly that; transitions failing closed in sa-core (v0.5.0 step 5).

- **Severity:** high. **Effort:** S now, M for the full table. **Roadmap:** section (h) and (a);
  v0.4.1 items 4, 5, 6; v0.5.0 step 5.
- **Evidence:** every hook exits 0 when sa-core is missing (`eval-gate.sh:8`, `worker-gate.sh:7`,
  `block-code-reads.sh:6`, `session-start.sh:4`); `tests/run.sh:520-528` asserts exactly that.
  `hookio get` exits 1 on bad JSON (`core/src/main.rs:107-114`) but the scripts read only stdout.
  The worker gate takes `dir` from the worker's own `status.json` (`worker-gate.sh:12`). The cached
  binary is never re-verified and a local build shadows it (`scripts/sa-native.sh:17-18,23`).
  Review P4; A5, A6, A8, A8c.
- **How it fails:** GitHub is unreachable on first use, or the platform has no prebuilt binary
  (`sa-native.sh:19`): all three gates are off for the session and only a stderr line or a
  `systemMessage` says so.
- **Root cause:** the hooks are both the control and the only place the control can fail safe, and
  sa-core is a download.
- **Fix:** roadmap (h): transitions fail closed in sa-core, hooks become nudges that say when they
  cannot run, PreToolUse denies with a literal reply, launcher re-verifies and checks the version.
- **Verify:** roadmap tests `gate-bad-json-says-so`, `native-cache-tampered`,
  `native-version-mismatch`, `worker-gate-foreign-dir`.

### C-05 Workers start from the remote's default branch, not from the integration branch

- **Status: fixed.** `scripts/superagent.sh` starts the router with `--settings '{"worktree":{"baseRef":"head"}}'`; `agents/worker.md` step 1 stops with `blocked: ticket folder is missing` when its worktree lacks the ticket. Test: `launch-sets-worktree-base` plus a static guard. Not verified: the real worker in a repository with a remote, and what the CLI does when the user passes a second `--settings`.

- **Severity:** high (in any cloned repository the parallel flow does not work as documented).
  **Effort:** S. **Roadmap:** section (b) "Changed after testing"; v0.4.1 item 2.
- **Evidence:** `scripts/superagent.sh:22` passes no `worktree.baseRef` setting.
  `docs/design/evidence/live/run1-main-probe` (HEAD of a worktree agent was `origin/main`), with the
  fix verified in `run2` and `run8`. `README.md:51` says workers build from committed files.
- **How it fails:** tickets are committed only on the local `integration/<ts>` branch
  (`scripts/commit-tickets.sh:21`). The worker's worktree is cut from `origin/main`, so
  `specs/tickets/001-*` does not exist there and the worker has nothing to build.
- **Root cause:** an untested assumption about the harness's worktree base.
- **Fix:** roadmap: `superagent.sh` adds `--settings '{"worktree":{"baseRef":"head"}}'`; the worker's
  first step fails loudly when its ticket folder is missing.
- **Verify:** roadmap test `launch-sets-worktree-base` (the fake `claude` in `tests/run.sh:308`
  records its arguments). Not verified by anyone yet: the real worker in a repository with a remote.

### C-06 The Stop gate spends its three blocks while subagents are still running

- **Status: fixed.** `scripts/eval-gate.sh` allows a stop silently, without counting a block, while the payload's `background_tasks` lists a task that is running (or has no status); `skills/review-loop/SKILL.md` asks for foreground subagents. Tests: `gate-allows-while-subagent-runs`, `gate-blocks-when-no-task-runs`. Not verified: the entries' real shape (the evidence recorded only the key and a count), so the test payloads are an assumption.

- **Severity:** high. **Effort:** S. **Roadmap:** section (b) "Seen live"; v0.4.1 item 3.
- **Evidence:** `scripts/eval-gate.sh:21-30` has no notion of a running subagent.
  `docs/design/evidence/live/run5-review-loop/timeline.txt`: three blocks in the first 12 seconds,
  then "released after 3 blocks" for the rest of the round.
- **How it fails:** the orchestrator starts the builder in the background, its turn ends, the gate
  blocks three times before any eval could pass, and is then off for that round.
- **Root cause:** "the turn ended" was read as "the agent claims done".
- **Fix:** roadmap: allow silently when the payload's `background_tasks` lists a running task; ask
  for foreground subagents in the review-loop text.
- **Verify:** roadmap tests `gate-allows-while-subagent-runs`, `gate-blocks-when-no-task-runs`.

### C-07 Team mode bypasses isolation, the gate and the merge path

- **Status: skipped.** Conflicts with a user decision: the user just enabled agent teams, so team mode is not cut. Its gaps (teammates are not gated, work is uncommitted in the main checkout, a building team ticket holds every merge) remain as documented.

- **Severity:** medium. **Effort:** M. **Roadmap:** section (f); v0.6.0 item 2; open decision 1.
- **Evidence:** teammates work uncommitted in the main checkout (`agents/teammate.md:9,14`) and are
  not gated (`README.md:104`; `worker-gate.sh:8` matches workers only). One building team ticket
  holds every solo merge and the checker (`agents/router.md:48`). "Undo" is "commit nothing"
  (`agents/merger.md:17`). Commit scope comes from `contract.md` (`merger.md:18`). Never run live
  (`README.md:41`). Review P5.
- **How it fails:** a team build fails lint. The merger commits nothing, the half-built files stay
  in the main checkout, and every later solo merge is told "queue until team NNN is merged".
- **Root cause:** a second execution model bolted onto a pipeline designed around worktrees.
- **Fix:** roadmap (f): cut the mode; split such work into a contract ticket plus solo tickets that
  wait for it.
- **Verify:** `board check` fails a `team` row with the removal message (`core/tests/board_check.rs`).

### C-08 Runtime status lives in tracked files that workers write in the main checkout

- **Severity:** medium. **Effort:** M. **Roadmap:** section (g); v0.5.0 step 1.
- **Evidence:** `agents/worker.md:15` runs `board set NNN building`, which resolves to the main
  checkout (`core/src/main.rs:100-104`), against `worker.md:32` "never touch the main checkout".
  This forces `':!specs/tickets'` in `agents/merger.md:14` and the selective `git add` in `:18`.
  `BOARD.md` is rewritten in place under a lock readers do not take (`core/src/board.rs:296-314`);
  `RD.md` is written with no lock (`:270`). Review P6.
- **How it fails:** the router reads `BOARD.md` with the Read tool while `board set` has truncated
  and is rewriting it, and sees a partial board; or a merge is refused because a status edit made
  the tree dirty in a way the special cases did not anticipate.
- **Root cause:** approval (belongs in git) and progress (does not) share one field.
- **Fix:** roadmap (g): `.super-agents/state.json` for runtime status, one lock, temp file plus
  rename for every write.
- **Verify:** roadmap test `core/tests/state_concurrency.rs`.

### C-09 Recovery paths contradict each other or do not exist

- **Status: partially fixed.** Done (v0.4.1 item 8): `agents/merger.md` step 0 finds and aborts a leftover `MERGE_HEAD` (`merge-head-recovery`); `scripts/watchdog-loop.sh` compares the problems with their minute counts masked, so a persisting problem is reported once (`watchdog-persisting-problem-silent`). The problem text itself is unchanged (no `kind :: details` form, no `renotify_min`). Remains: the restart instruction in `agents/router.md` ("continues in the existing worktree") still contradicts `isolation: worktree`, because the roadmap's replacement needs the branch recorded per ticket (`state.json`); one heartbeat per worktree; no notion of a flaky eval.

- **Severity:** medium. **Effort:** S for the v0.4.1 parts, M overall. **Roadmap:** section (g);
  v0.4.1 item 8; v0.5.0 step 7; v0.6.0 item 3.
- **Evidence:** "start a fresh worker that continues in the existing worktree"
  (`agents/router.md:57`) against `isolation: worktree` (`agents/worker.md:7`). The scan groups
  every worktree's heartbeat by ticket (`core/src/scan.rs:48-61`). Change detection compares text
  that contains minute counts (`scripts/watchdog-loop.sh:8`, `scan.rs:124,146`), so a persisting
  problem wakes the watchdog model every interval. No step handles a leftover `MERGE_HEAD`. No
  notion of a flaky eval. Review P7.
- **How it fails:** a worker dies at minute 20. Every 10 minutes the watchdog is woken with
  "silent for 30 min", "silent for 40 min", and so on; the router's restart instruction cannot be
  followed as written.
- **Root cause:** recovery was written as prose after the happy path, without a single record per
  ticket to recover from.
- **Fix:** roadmap (g) table "Recovery paths".
- **Verify:** roadmap tests `merge-head-recovery` and the "persisting problem is silent on the
  second round" case in `core/tests/board_scan.rs`.

### C-10 Agents have more power than their roles need

- **Status: partially fixed.** Done (v0.4.1 item 7): `agents/reviewer.md` and `agents/builder.md` have `tools:` allowlists (no Agent, web tools or MCP connectors; the reviewer keeps the browser tools and has no Edit or Write), no agent uses `disallowedTools`, and the checker is no longer described as read-only. Guard in `tests/run.sh`. Behaviour change: reviewer and builder lose the tools named above. Remains: the watchdog keeps Edit (dropping it needs a `watchdog set` command), the merger gets no Agent tool yet, and the PreToolUse deny rules are v0.5.0 step 6.

- **Severity:** medium. **Effort:** S. **Roadmap:** section (d); v0.4.1 item 7; v0.5.0 step 6.
- **Evidence:** `agents/reviewer.md:4` is a three-tool denylist; `agents/builder.md:1-5` has no
  `tools` line; both run under the session's permissions and, in the parallel flow,
  `--permission-mode auto` (`scripts/superagent.sh:21`). `agents/watchdog.md:4` has Edit;
  `agents/checker.md:3-4` says "read-only" and lists Bash. Review P8; `evidence/live/run6-tool-lists`.
- **How it fails:** a prompt-injected reviewer (it reads the diff, which is attacker-influenced
  text in a hostile repository) has Bash, Agent and every MCP connector the user installed.
- **Root cause:** `disallowedTools` and "read-only" in a description were treated as controls.
- **Fix:** roadmap (d) tools table.
- **Verify:** roadmap consistency test: every `agents/*.md` has a `tools:` line and none has
  `disallowedTools`.

### C-11 Duplicated mechanisms and drift inside the plugin

- **Status: partially fixed.** Done (v0.4.1 item 9): `scripts/init-project.sh` ignores only the plugin's own files under `specs/<name>/` instead of `specs/*`, and replaces the two legacy lines (`init-specs-own-files-tracked`, `init-legacy-ignore-removed`). One loop rule was aligned by hand: the worker now re-runs every eval after a fix, like the review-loop (C-03). Remains: the three loop definitions are still three prompts (no `templates/loop.md`; round limits 5, 3 and 3); the 140-line first-time-user shell parser; byte compatibility with the deleted Python in `core/src/hookio.rs` and `core/src/board.rs`.

- **Severity:** low to medium. **Effort:** M. **Roadmap:** section (e) and (h); v0.4.1 items 6
  and 9; v0.6.0 items 1, 4 and 6.
- **Evidence:** three loop definitions with different rules (`skills/review-loop/SKILL.md:55-57`,
  `agents/worker.md:20`, `agents/teammate.md:15`). A 140-line shell parser for the first-time-user
  block with probed bypasses (`scripts/block-code-reads.sh`; A7). Byte compatibility with deleted
  Python (`core/src/hookio.rs:75-154`, `core/src/board.rs:27-28`). Setup ignores `specs/*`
  (`scripts/init-project.sh:31`). Review P9.
- **How it fails:** a rule is tightened in the review-loop (for example "re-test every eval") and
  the worker keeps the weaker one, so the parallel flow is silently less strict than the
  single-feature flow.
- **Root cause:** each flow was written as its own prompt.
- **Fix:** roadmap (e) `templates/loop.md`; v0.6.0 allowlist for the first-time-user; v0.4.1 item 9
  for the ignore patterns.
- **Verify:** roadmap consistency tests in the v0.6.0 list.

---

## Part 2. New issues

### N-01 A ticket branch can change other tickets' approved evals, `review.md` and `CLAUDE.md`

- **Status: fixed** in `agents/merger.md` step 2 with a test in `tests/run.sh`. The doc's `evidence` exclude missed files inside the folder; the shipped one is `evidence/*`.

- **Severity:** high. **Effort:** S. **Roadmap:** not covered. (Roadmap (b) records a copy of the
  fingerprint at `start`, which protects a ticket already building; a ticket that has not started
  reads the tampered fingerprint.)
- **Evidence:** `agents/merger.md:15`. The approved-file check is scoped to the ticket being
  merged: `git diff --name-only HEAD...$SHA -- 'specs/tickets/NNN-*/evals.md'
  'specs/tickets/NNN-*/RD.md' 'specs/tickets/NNN-*/.evals.sha256'`. Nothing looks at other ticket
  folders, `BOARD.md`, `review.md`, `CLAUDE.md`, `AGENTS.md` or `.gitignore`.
  `scripts/check-evals.sh:44-48` then trusts whatever fingerprint is in the main checkout.
- **Probed:** a branch for ticket 001 appended a line to `specs/tickets/002-b/evals.md`, rewrote
  `002-b/.evals.sha256` with `super-agents fingerprint`, and replaced `review.md`. Output:

  ```
  scoped: []
  all changed:
  review.md
  specs/tickets/002-b/.evals.sha256
  specs/tickets/002-b/evals.md
  src.txt
  check-evals --passed on tampered 002 after merge:
  OK: specs/tickets/002-b
  ```

- **How it fails:** worker 001's change breaks an eval that belongs to ticket 002. Being "helpful",
  it relaxes 002's eval and refreshes the fingerprint in its worktree (`check-evals` told it the
  file "changed after the user approved it", `check-evals.sh:52`). The merger's check prints
  nothing, the merge lands, and ticket 002 is now built and gated against evals the user never
  approved. The same path changes `review.md`: its "Ignore" list steers every later reviewer and its
  "How to test this project" commands are what the merger runs (`merger.md:17`).
- **Root cause:** the check lists what the ticket must not change in its own folder instead of
  listing the only spec files a branch may change at all.
- **Fix:** invert the check in `agents/merger.md` step 2. For a solo ticket NNN:

  ```
  git diff --name-only HEAD...$SHA -- specs/tickets review.md CLAUDE.md AGENTS.md .gitignore \
    ':(exclude)specs/tickets/NNN-*/results.md' ':(exclude)specs/tickets/NNN-*/evidence'
  ```

  must print nothing; otherwise merge nothing and report the files. For a fix branch
  (`fix <branch>`, no ticket) drop the two excludes. Keep the existing `git status --short` check of
  the main checkout's copies. Add a fixture next to H1 (`tests/run.sh:452`) that builds the branch
  from the probe above and asserts the command prints the three spec paths, and a static guard that
  `merger.md` contains `review.md CLAUDE.md`. When roadmap v0.5.0 lands, move the command into
  sa-core (`board merge-check NNN <sha>`) so the merger cannot paraphrase it.
- **Alternatives rejected:** (1) a PreToolUse deny on Edit/Write of other tickets' files: the live
  run made 0 Edit and 0 Write calls, every change went through Bash (`design-changes.md:306`).
  (2) Fingerprint every ticket again at merge time against a stored copy: needs the v0.5.0 state
  store; the pathspec is one line today. (3) Forbid workers from touching `review.md` by prompt
  only: that is the current state.
- **Verify:** `bash tests/run.sh` with the new fixture; by hand, the probe above must print the
  three paths instead of `scoped: []`.

### N-02 `RD.md` is approved by the user but not fingerprinted

- **Status: fixed.** `board set <X> ready` writes a second line to `.evals.sha256` (`<hex>  RD.md`): sha256 of `RD.md` with CRLF read as LF and the first `**Status:**` line removed (`core/src/board.rs` `fingerprint_rd`, `sa-core fingerprint-rd`). `scripts/check-evals.sh --passed` compares it and fails with "RD.md changed after the user approved it"; a one-line file from an older version still passes. `classify-risk` writes the Risk line only while the status is `draft`. Tests: `core/tests/board_set.rs`, `eval-rd-tampered`, `eval-rd-status-change-ok`, `eval-rd-one-line-fingerprint`. Both lines are written when a draft is approved, not on a later `ready` (C-02).

- **Severity:** medium. **Effort:** S to M. **Roadmap:** not covered (roadmap (d) rule 1 denies
  Edit/Write on `RD.md`, which it states is a convenience that matched nothing live).
- **Evidence:** `core/src/board.rs:273-278` fingerprints `evals.md` only. `README.md:89` and
  `skills/write-eval/SKILL.md:21` present `RD.md` and `evals.md` together as what the user approves.
  The risk level, which sets the reviewer's threshold (`agents/reviewer.md:19`), is read from
  `RD.md`: by the orchestrator at `skills/review-loop/SKILL.md:18` and by the worker from **its own
  copy** (`agents/worker.md:19`). `skills/classify-risk/SKILL.md:15` rewrites the `**Risk:**` line
  "silently" at any status.
- **Probed:** after approval, `sed -i 's/Risk:\*\* high/Risk:** low/'` on a ticket's `RD.md`;
  `super-agents check-evals <dir> --passed` printed `OK` and exit 0.
- **How it fails:** single-feature flow: the builder (all tools, same checkout) narrows "Must not
  touch" or lowers Risk from high to low; the next round's reviewer reports blockers only; nothing
  detects it. Parallel flow: the worker's reviewer runs at the lowered threshold; the merger's diff
  (`merger.md:15`) does catch the changed `RD.md`, but only after the whole build, and the fix is a
  full redo.
- **Root cause:** `board set` must rewrite the `**Status:**` line inside `RD.md`, so the file as a
  whole could not be hashed, and it was left out.
- **Fix:** in `core/src/board.rs`: add `fingerprint_rd(dir)` = sha256 of `RD.md` with the first
  `**Status:**` line removed (reuse `STATUS_LINE`, `:239-240`) and CRLF read as LF. On `ready`,
  write it as a second line of `.evals.sha256` (`<hex>  RD.md`); keep line 1 unchanged so existing
  one-line files and `tr -d ' \r\n' < "$fp"` readers need a small change only:
  `scripts/check-evals.sh:52` compares line 1 as today and, when a second line exists, compares it
  to `sa-native.sh fingerprint-rd "$rd"` and fails with "RD.md changed after the user approved it".
  A one-line file keeps passing (no re-approval), with one release of grace. Expose
  `sa-core fingerprint-rd <file>` in `core/src/main.rs`. Change `classify-risk/SKILL.md:15` to
  write the Risk line only while the status is `draft`. Tests: `core/tests/board_set.rs` (two-line
  file; status change does not alter line 2), `tests/run.sh` check-evals section (edited Risk
  fails; one-line file passes).
- **Alternatives rejected:** (1) move Status out of `RD.md`: that is roadmap (g) and a larger
  change; this fix is compatible with it. (2) Hash the whole file and re-hash on each status
  change: every `board set` would then launder edits, which is C-02 again. (3) Have the router pass
  the risk to the worker: fixes one field in one flow.
- **Verify:** `cargo test --locked` in `core/`; `bash tests/run.sh`; the probe must print
  `FAIL: RD.md changed after the user approved it`.

### N-03 The worker gate matches one exact agent name

- **Status: skipped.** Conflicts with a user decision: `tests/run.sh` (the `#7` comment above `wgate-bare-worker`) deliberately asserts that a bare `worker` and another plugin's `worker` are NOT gated, and the `.claude/agents` copies stay (N-04). The tension is real: a worker started from the project copy as `worker` is not gated. Near-miss names are now tested (`wgate-coworker`, `wgate-teammate`; N-11).

- **Severity:** medium. **Effort:** S. **Roadmap:** not covered (the roadmap keeps the
  `super-agents:worker` literal).
- **Evidence:** `scripts/worker-gate.sh:8` is `= super-agents:worker`, while
  `scripts/block-code-reads.sh:7` uses the regex `(^|:)first-time-user$`. The repository ships an
  un-namespaced copy of the worker at `.claude/agents/worker.md`. `README.md:23` documents a
  second install form (`@skills-dir`) whose `agent_type` prefix the review lists as unverified
  (`design-review.md:121`).
- **Probed:** same failing ticket, same payload except `agent_type`:
  `super-agents:worker` gave `"decision": "block"`; `worker` gave no output and exit 0.
- **How it fails:** in a session opened in this repository both `worker` and `super-agents:worker`
  are offered as agent types with identical descriptions. A worker started as `worker` finishes
  with failing evals and no gate runs. If the `@skills-dir` install yields a different prefix, the
  gate is off for every user of that install, silently.
- **Root cause:** two hooks written at different times with different matching rules.
- **Fix:** `scripts/worker-gate.sh:8`: `re='(^|:)worker$'; [[ $(get agent_type <<<"$in") =~ $re ]]
  || exit 0`. Add to the worker-gate section of `tests/run.sh` (`:178`): a payload with
  `agent_type: worker` blocks; `agent_type: coworker` and `super-agents:teammate` do not.
- **Alternatives rejected:** keeping the literal and deleting the `.claude` copy only (N-04) leaves
  the `@skills-dir` question open; matching `*worker*` would gate unrelated agents.
- **Verify:** `bash tests/run.sh`; rerun the probe and expect a block for both names.

### N-04 `.claude/agents` and `.claude/skills` duplicate the plugin and shadow its names

- **Status: skipped.** Conflicts with a user decision: the user asked for the `.claude/agents` and `.claude/skills` copies. Drift, the one part that can be closed without deleting them, is now guarded: `tests/run.sh` fails when a copy differs from its plugin file (the `model:` lines of `router.md` and `watchdog.md` excepted). Shadowing (each agent offered twice) remains.

- **Severity:** medium. **Effort:** S. **Roadmap:** not covered (added after it, commit `aab1bdc`).
- **Evidence:** `diff -r agents .claude/agents` reports only `general-purpose.md` as extra;
  `diff -r skills .claude/skills` is empty: 19 files are byte-identical copies. The commit message
  says they "must be kept in sync". Nothing in `tests/run.sh` reads `.claude/agents` or
  `.claude/skills` (its only `.claude` matches are worktree fixtures at `:137-141`, `:246-249` and
  the manifests at `:484`, `:502-503`). `.claude/agents/router.md:4` still lists
  `Agent(super-agents:worker, ...)`. `.claude/agents/general-purpose.md:4` pins
  `model: claude-fable-5-2`.
- **Observed in this session** (opened in this repository with the plugin installed): the agent
  list offers each of the 11 agents twice (`worker` and `super-agents:worker`, and so on), and the
  skill list offers `classify-risk`, `fix-bug`, `write-eval`, `write-tickets` twice. The built-in
  general-purpose agent is replaced by the project file.
- **How it fails:**
  1. Drift: a fix to `agents/merger.md` (for example N-01) is not mirrored. A contributor testing in
     this repository who starts `merger` runs the old rules and believes the fix works or does not.
  2. Shadowing: the model picks `reviewer` instead of `super-agents:reviewer`; hooks keyed on the
     namespaced name do not apply (N-03).
  3. Allowlist: `claude --agent router` (the project copy) binds descendants to `super-agents:*`
     names; without the plugin installed every dispatch fails, and "fixing" the copy by removing the
     prefix produces workers no gate recognises.
  4. Cost and access: every general-purpose subagent in this repository, for every contributor,
     runs on the pinned model, whether or not their account has it (see N-08 for prices).
  5. `claude plugin eval .` runs in this repository; whether its sandbox also loads `.claude/` was
     not verified. If it does, `classify-risk-discovery` cannot tell which copy fired.
- **Root cause:** unclear. The commit gives no reason for the copies; the likely intent is to use
  the agents while developing without installing the plugin. `README.md:16` already provides that:
  a local-path marketplace "loads the repo in place, so your edits stay live".
- **Fix:** delete `.claude/skills/` and the 11 plugin copies in `.claude/agents/`. Decide
  separately whether `general-purpose.md` belongs in the repository: if it is a personal
  preference, move it to the maintainer's `~/.claude/agents/`; if it is project policy, keep it and
  say why in `README.md` "Development". Add one guard to the consistency section of `tests/run.sh`
  (`:467`): fail when `.claude/agents/<n>.md` exists for an `<n>` in `agents/`, or
  `.claude/skills/<n>` for an `<n>` in `skills/`.
- **Alternatives rejected:** (1) symlinks from `.claude/` into `agents/` and `skills/`: removes
  drift, keeps the shadowing, and symlinks are not available in the Windows CI job
  (`tests/run.sh:425`). (2) A `diff -r` sync test: keeps both copies and the shadowing, and doubles
  every prompt edit. (3) Keep the copies and drop the plugin install for development: then the
  hooks, which only the plugin registers, are not exercised.
- **Verify:** `ls .claude/skills 2>/dev/null; ls .claude/agents` shows at most
  `general-purpose.md`; `bash tests/run.sh` passes with the new guard; a new session in the repo
  lists each agent once.

### N-05 A worker that stops to ask the user is blocked by its own gate

- **Status: fixed.** New heartbeat phase `waiting` (`scripts/job-status.sh`): `scripts/worker-gate.sh` lets that stop through before the block counter, `core/src/scan.rs` reports `PROBLEM NNN <who> waits for the user: <question>` instead of "silent", and `agents/worker.md` asks through it instead of `SendMessage`, which it does not have. Tests: `wgate-waiting-phase`, `scan-waiting-for-user`, `core/tests/board_scan.rs`. Not done: step 6 (`job await` in v0.5.0). Not verified live: that the router resumes the worker with the answer.

- **Severity:** medium. **Effort:** S. **Roadmap:** partly (roadmap (b) gives sessions
  `loop await`; for workers it offers only `job blocked`, so the same gap remains in v0.5.0).
- **Evidence:** `agents/worker.md:35`: "`SendMessage` to `main` ... then end your turn saying you
  are waiting. You will be resumed with the answer." `agents/worker.md:4`: the tool list has no
  `SendMessage`, and a subagent's `tools:` list is enforced (`design-changes.md:290`).
  `scripts/worker-gate.sh:13-20`: the only phase that passes without passing evals is `blocked`.
  `core/src/scan.rs:112-128`: any phase other than `blocked` or `done` is reported once silent past
  the limit. `agents/teammate.md:4,14,17` has the same tool mismatch (whether the agent-teams
  harness adds messaging tools on its own was not verified).
- **Probed:** a worker in phase `building` with no results, SubagentStop payload for
  `super-agents:worker`: `"decision": "block"`, "Not done yet ... Fix and re-test", and
  `.job/gate_blocks` became 1.
- **How it fails:** the worker meets a real product question. It cannot call `SendMessage`. It
  ends its turn with the question. The gate blocks it three times with "fix and re-test", pushing
  it to guess instead of ask, which is the outcome `write-tickets/SKILL.md:8` and `worker.md:35`
  exist to prevent. If it holds out, the cap is spent, and unless it later runs
  `job-status building` (which resets the counter, `scripts/job-status.sh:15`) its real "done" stop
  is ungated. Meanwhile the watchdog reports it as silent after `stale_min`.
- **Root cause:** the session gate has `awaiting_user`; the worker gate has no equivalent, and the
  prompt names a tool the agent does not have.
- **Fix:**
  1. `scripts/job-status.sh:4`: document a sixth phase, `waiting`.
  2. `scripts/worker-gate.sh:13`: `case "$(get phase <"$st")" in blocked|waiting) exit 0;; esac`.
     It exits before the counter, so waiting does not spend blocks.
  3. `core/src/scan.rs:107-111`: treat `waiting` like `blocked` with its own text
     (`PROBLEM NNN worker waits for the user: <note>`), so the router is told once and the silent
     check does not fire.
  4. `agents/worker.md:35`: "run `super-agents job-status waiting "<the question>"`, then end your
     turn; your final message is the question with 2-3 options. When resumed, run
     `super-agents job-status building`." Remove `SendMessage` from the sentence.
     `agents/router.md:54` already relays answers with `SendMessage`.
  5. Tests: `tests/run.sh` worker-gate section (`waiting` passes and leaves `gate_blocks` absent);
     `core/tests/board_scan.rs` (a `waiting` job older than `stale_min` yields the waiting line,
     not "silent").
  6. Carry into roadmap v0.5.0 as `super-agents job await "<question>"`.
- **Alternatives rejected:** (1) add `SendMessage` to the worker's tools: the turn still has to
  end and the gate still blocks. (2) Tell the worker to use `blocked`: the router treats blocked as
  failure (`worker.md:35`, `scan.rs:107`) and the user sees a failed ticket instead of a question.
  (3) Exempt any stop whose last message contains a question mark: text matching in a gate.
- **Verify:** `bash tests/run.sh`; `cargo test --locked`; rerun the probe after
  `super-agents job-status waiting "q"` and expect no output, exit 0, and no `.job/gate_blocks`.

### N-06 The router is a single point of failure and its state exists only in its context

- **Status: partially fixed.** First step only, prompts with a static guard: the checker records its verdict and the checked commit in `.super-agents/checks/NNN.txt`; the router's "On start" classifies tickets from the board, that file and the heartbeats (`done` without `CONFIRMED OK` = start the checker; `building` with heartbeat phase `done` = acceptance read, then merger), and "Finish" requires the file for every ticket. Doc correction: the location below (`specs/tickets/NNN-*/evidence/check.txt`) was wrong. Probed: an untracked file there survives `super-agents drop-specs` and leaves an untracked `specs/` in the branch, or is swept into `commit-tickets`. `merge.txt` (step 2) was not added: nothing in step 3 reads it. Remains: rounds per ticket, the merge queue, standing approval and the watchdog id still live only in the router's context; `drop-specs` does not check the verdicts itself. Not verified: any of this with a real router, and whether its Glob sees git-ignored `.job/` files.

- **Severity:** medium. **Effort:** M. **Roadmap:** partly (v0.5.0 step 1 `state.json` records
  status, worktree and branch; v0.6.0 item 1 moves round counting into the worker; the merge queue
  and the check verdicts are not covered).
- **Evidence:** held only in the router's conversation: rounds per ticket (`agents/router.md:47`),
  the merge queue and the team hold (`:48`), which tickets the checker confirmed (`:49`, `:51`),
  standing approval "keep going" (`:36`), the watchdog's agent id (`:41`), which agent builds which
  ticket ("answer from your own records", `:54`). The only recovery step is a Glob for heartbeat
  files (`:27`). The router has no write tool (`:4`), so it cannot persist anything itself. The
  merger sets `done` before the checker runs (`agents/merger.md:18`, then `router.md:49`). The
  frontmatter sets no compaction window, unlike the watchdog (`agents/watchdog.md:8`). Team tickets
  are "not resumable" (`README.md:109`).
- **How it fails:** the terminal closes after ticket 003 merged but before its check came back. On
  restart the board says 003 is `done`. Nothing records that it was never checked, so the Finish
  condition (`router.md:51`, "every ticket's check is `CONFIRMED OK`") is evaluated from an empty
  memory and `drop specs` can run with an unchecked ticket. A worker that finished and was accepted
  but not yet merged looks the same as one that is still building (board `building`, heartbeat
  `done`). Whether the router's Glob sees git-ignored `.job/` files was not verified.
- **Root cause:** the orchestrator was made unable to write (a good property) without giving the
  agents that can write a place to record orchestration facts.
- **Fix (ahead of v0.5.0, files only):**
  1. `agents/checker.md:16-18`: besides its reply, write the first line of the verdict and the
     checked commit (`git rev-parse HEAD`) to `specs/tickets/NNN-*/evidence/check.txt`. The checker
     may already write under that folder (`checker.md:8`).
  2. `agents/merger.md:20`: after a merge, append `merged <sha>` to the same file's sibling
     `evidence/merge.txt` (uncommitted is fine; it is read from the main checkout).
  3. `agents/router.md:27` "On start" step 2: for each ticket, classify from files, not memory:
     `done` on the board with `check.txt` starting `CONFIRMED OK` = finished; `done` without it =
     start the checker; `building` with heartbeat phase `done` = run the acceptance read and queue
     the merger; `building` with a live heartbeat = running; `building` with a stale or missing
     heartbeat = ask the user. `router.md:51` Finish: require `check.txt` for every ticket instead
     of relying on recollection.
  4. `scripts/drop-specs.sh`: no change now (the files are untracked evidence); when v0.5.0 lands,
     move both facts into `state.json` (`verified`, plus a `checked` field) and make `drop-specs`
     require `checked` for every ticket.
  5. Static guards in `tests/run.sh` (`:476-480` style): `checker.md` names `check.txt`;
     `router.md` Finish names it.
- **Alternatives rejected:** (1) give the router Write: removes the property that it cannot touch
  the tree (`README.md:73`). (2) A new board status `merged` between `building` and `done`: changes
  `STATUSES` (`core/src/board.rs:26`), `drop-specs.sh:19`, `merger.md:14` and every test fixture for
  something v0.5.0 replaces. (3) Rely on `claude --resume`: restores memory only if the same
  session can be resumed, and not for team tickets.
- **Verify:** the roadmap's live smoke (v0.5.0 item 8), extended: kill the router after the first
  merge, restart, and check that the checker is started for the merged ticket and `drop specs` is
  not run before its `check.txt` exists.

### N-07 The checker shares the main checkout with the next merge; two reproducers share a port

- **Status: fixed.** `agents/router.md` "When work comes back" step 3 makes a merge, its check and any reproducer fix one queue slot and allows one reproducer at a time; static guard in `tests/run.sh`. Prompt rule only: not run live.

- **Severity:** medium. **Effort:** S. **Roadmap:** not covered.
- **Evidence:** `agents/router.md:48` serialises mergers ("Only one merger runs at a time") and
  holds merges and the checker only for a building team ticket. `router.md:49` starts the checker
  after a merge; nothing says the next queued merge waits for it. The checker serves the app from
  the main checkout on port 3000 (`agents/checker.md:11`), and the merger changes that same working
  tree with `git merge --no-ff --no-commit`, then lint and build, and may `git merge --abort`
  (`agents/merger.md:16-17`). The reproducer has one fixed port and account, 3090 and `t090`
  (`agents/reproducer.md:13`), and nothing limits it to one instance. Read only; not run live.
- **How it fails:** tickets 001 and 002 are both accepted. 001 merges; the checker starts the app
  from the main checkout. The router starts the merger for 002. A dev server with file watching
  now serves a half-merged, uncommitted 002, the checker sees a break "twice" (both loads hit the
  staged merge), reports `BROKEN` against 001, and the reproducer, in a clean worktree, answers
  `NOT REPRODUCED`. The user is told ticket 001 has an unresolved check. With two `BROKEN` tickets,
  two reproducers start on port 3090 and the second one tests the first one's server
  (the same "use what answers" habit as `agents/tester.md:13`).
- **Root cause:** the queue rule covers merger against merger, not the other agents that use the
  main checkout or a fixed port.
- **Fix:** `agents/router.md:48-49`: make "merge, check, and any reproducer fix for that ticket"
  one queue slot: "Do not start the next merger until the checker for the previous merge has
  replied and, if it said `BROKEN`, the reproducer has replied and its fix (if any) is merged and
  re-checked. One reproducer at a time." Add a static guard in `tests/run.sh` next to `:479`.
- **Alternatives rejected:** (1) give the checker `isolation: worktree` so it tests the merge
  commit in its own tree: better throughput, but with the worktree base problem (C-05) unfixed it
  would test `origin/main`, and two checkers would then share port 3000; revisit after v0.4.1.
  (2) Per-ticket reproducer ports: needs a ticket number the reproducer is not given for fix-only
  work (`router.md:49`).
- **Verify:** the static guard; in the live smoke, the hook log must show no merger start between
  a checker's start and stop.

### N-08 Model, effort and turn limits are set without a stated rule or a cost ceiling

- **Status: partially fixed.** Done (steps 1-3 and 6): `maxTurns` on builder 150, tester 80, reviewer 80, merger 60, checker 80, teammate 200; `effort: high` set explicitly on merger and reviewer; `first-time-user` pinned to `sonnet`; `README.md` has a table of model, effort, turn limit and why, which `tests/run.sh` compares with the frontmatter; the router's plan shows the total agent runs. The limits are ceilings picked above the one measured toy run, not tuned. The evidence table above is out of date: the router now runs on `claude-fable-5-2` (commit `c94bb67`). Remains: step 4 (cost per agent type in a live smoke) and step 5 (model changes decided from it); no budget ceiling.

- **Severity:** medium (cost), low (correctness). **Effort:** S for limits, M to measure.
  **Roadmap:** not covered (roadmap v0.5.0 item 8 records one data point: a one-round loop cost
  $0.41 on Sonnet).
- **Evidence (frontmatter of `agents/*.md`):**

  | Agent | model | effort | maxTurns |
  |---|---|---|---|
  | router | opus | high | none |
  | worker | sonnet | high | 200 |
  | teammate | sonnet | high | none |
  | reproducer | sonnet | high | 120 |
  | watchdog | sonnet | medium | 400 |
  | merger, checker, tester, reviewer, builder | sonnet | not set | none |
  | first-time-user | inherit | not set | none |
  | `.claude/agents/general-purpose.md` | claude-fable-5-2 | not set | none |

  `scripts/superagent.sh:21-22` starts the run in `--permission-mode auto` with no budget argument.
  The router's plan shows "how many agents run at once" (`agents/router.md:34`), not a total.
- **Reference prices** (Anthropic API list prices per million tokens, input / output, from the
  Claude API reference bundled with Claude Code, cached 2026-11-03): Fable 5.2 $8 / $40;
  Opus 5.5 $4 / $20; Sonnet 5.5 $2 / $10; Haiku 5.5 $0.10 / $0.50. Which versions the aliases
  `opus` and `sonnet` resolve to in a given CLI was not verified; `evidence/live/costs.txt` shows
  `claude-sonnet-5-5` and `claude-haiku-5-5` in the test runs.
- **Observations:**
  1. The router is the longest-lived session, receives every worker report, watchdog message and
     user message, and runs on the most expensive tier in the plugin at high effort. Its prompt
     describes its job as tracking and dispatch (`router.md:9`); the one judgement it makes, the
     acceptance read (`router.md:46`), is a mechanical comparison that roadmap (e) moves into
     sa-core.
  2. Effort is set high where a gate and a reviewer follow (worker, teammate) and left at the
     default where nothing follows: the merger resolves conflicts by hand and commits after lint
     and build only (`agents/merger.md:16-17`); the reviewer is the independent check. No file
     says this split is intended.
  3. The reviewer runs on the same model alias as the builder and the worker since `aab1bdc`
     (both were `inherit` before). Independence is by fresh context only. This may be fine; it is
     undocumented.
  4. The watchdog is a 400-turn model session whose loop wakes it every interval for a persisting
     problem (C-09). Each wake is a model turn with Bash and file reads (`agents/watchdog.md:15`).
  5. Six agents and the router have no `maxTurns`. In auto mode nothing bounds a builder or a
     merger that loops.
  6. A solo ticket costs at least five agent runs (worker, tester, reviewer, merger, checker), and
     up to four tester and four reviewer runs with three fix rounds (`agents/worker.md:20`), plus
     reproducer, merger and checker again on a break (`router.md:49`). The user is not shown this.
  7. `first-time-user` inherits whatever the session runs on, so its cost is unpredictable.
  8. Aliases float with the CLI version while the prompts are tuned by hand and the evals are run
     by hand (`README.md:126`), so behaviour can change with no change in this repository.
- **How it fails:** a ten-ticket run on a real codebase: ten workers at high effort, each with up
  to eight verifier runs, one opus session accumulating all reports, a watchdog woken every ten
  minutes per stuck worker, and no ceiling. The bill is discovered afterwards.
- **Root cause:** models were assigned per agent as each was written; there is no cost model and
  no measurement beyond one data point.
- **Fix (in this order; none of it changes a model on belief alone):**
  1. Limits (S): add `maxTurns` to `builder`, `tester`, `reviewer`, `merger`, `checker`,
     `teammate`. Pick values from the live smoke's observed turn counts with generous headroom, so
     a healthy run never hits them. A static guard in `tests/run.sh`: every `agents/*.md` except
     `router.md` and `first-time-user.md` has `maxTurns`.
  2. State the rule (S): one table in `README.md` "The agents": model, effort, and why. Set
     `effort:` explicitly on `merger` and `reviewer` rather than inheriting a default.
  3. Show the total (S): `agents/router.md:34` plan line: "N tickets, at least 5 agent runs each,
     up to M at once".
  4. Measure (M): have the live smoke (roadmap v0.5.0 item 8) record cost per agent type from the
     stream output, as `evidence/live/costs.txt` does per run today.
  5. Then decide, as the maintainer's call, with the smoke as the test: the watchdog on `haiku`
     once C-09's dedupe is fixed (it forwards and summarises); the router on `sonnet` once
     acceptance is mechanical (v0.5.0). Each is a one-line frontmatter change that the smoke
     either survives or does not.
  6. `first-time-user`: pin a model so its cost does not depend on the caller.
- **Alternatives rejected:** (1) downgrade models now to save money: no measurement says the
  prompts hold; the cost of a wrong merge exceeds the saving. (2) Replace the watchdog model with
  the bash loop reporting straight to the router: the router has no Monitor or Bash tool and giving
  it one breaks `router.md:4`. (3) Pin dated model ids everywhere: trades silent drift for manual
  upgrades in eleven files; decide after item 4.
- **Verify:** the static guard for `maxTurns`; a `costs.txt` with one line per agent type from the
  smoke run; for each model change, the smoke's mechanical pass criteria.

### N-09 A release is not tied to the source its binaries were built from

- **Status: fixed.** `release.yml` `publish` fetches full history and refuses to publish when `core/` at the tag differs from the draft's `targetCommitish`; it also asks the released Linux binary for its version; the `test` job runs `cargo test --locked`; `ci.yml` pins the same `RUST_TOOLCHAIN` as `build-core.yml`; `build-core.yml` moves an existing draft's target to the commit it builds from (without that a re-run from another ref would leave a stale target). Static guards in `tests/run.sh`. Doc correction: the diff does not exclude `core/Cargo.lock` as written below, because a changed lock file changes the dependencies that are built in. Not verified: no workflow was run (no throwaway tag in a fork).

- **Severity:** low to medium. **Effort:** S. **Roadmap:** not covered (the review calls the
  supply chain sound, `design-review.md:30`; that holds for binary-to-checksum, not source-to-binary).
- **Evidence:** `build-core.yml` builds from whatever ref is dispatched and records it as the draft
  release target (`.github/workflows/build-core.yml:45`, `--target "$GITHUB_SHA"`). `release.yml`
  checks that the tag equals the `plugin.json` version and that the checksum file exists
  (`:21-25`), then that the draft's binaries match the committed checksums (`:43-50`). Nothing
  compares `core/` at the tag with `core/` at the commit the binaries were built from. The release
  `test` job runs ShellCheck and `tests/run.sh` on Linux only (`release.yml:26-29`): no
  `cargo fmt`, `clippy` or `cargo test`, no macOS or Windows. CI uses the runner's default Rust
  toolchain (`.github/workflows/ci.yml:26-29`) while the release build pins 1.99.1
  (`build-core.yml:17`).
- **How it fails:** binaries are built from branch A; a fix to `core/src/board.rs` is committed
  afterwards together with the checksums; the tag is pushed. The release publishes binaries that
  lack the fix while the tagged source has it, and `tests/run.sh` in the release job passes because
  it builds `core/` from source (`tests/run.sh:10`) instead of testing the released binary.
- **Root cause:** two workflows joined by a manual step, with the checksum as the only link.
- **Fix:** in `release.yml`:
  1. `publish` job, before "Publish": check out with `fetch-depth: 0`, read the draft's
     `targetCommitish` (`gh release view "$GITHUB_REF_NAME" --json targetCommitish`), and fail
     unless `git diff --quiet <that sha> "$GITHUB_SHA" -- core/ ':!core/Cargo.lock'` exits 0, with
     the message "sa-core sources changed after the binaries were built; re-run build-core.yml".
  2. `test` job: add `cargo test --locked` in `core/`.
  3. `ci.yml`: install the same `RUST_TOOLCHAIN` as `build-core.yml` so `clippy -D warnings` cannot
     start failing on a toolchain bump nobody chose.
  Add static guards beside `tests/run.sh:534-537` (`release.yml` mentions `targetCommitish`).
- **Alternatives rejected:** (1) build in the release workflow itself: the checksums could then
  not be committed before the tag, which is the property the current design is built on. (2)
  Reproducible-build comparison: far more work than a source diff for the same assurance here.
- **Verify:** `bash tests/run.sh` (static guard); on a throwaway tag in a fork, change a comment in
  `core/src/main.rs` after the build and confirm the publish job fails.
- **Note:** a tag `v0.4.0` exists on the unmerged branch `release/v0.4.0` while this branch is
  0.3.1 without `dist/checksums/v0.4.0.txt`. That matches the documented order (publish, then merge
  to main, `README.md:123`); whether v0.4.0 was published was not checked.

### N-10 Portability: what is supported is narrower and vaguer than the code suggests

- **Status: partially fixed.** Done: `README.md` "Install" has a platform table (item 1, with the macOS 12.3 minimum of item 3); `scripts/session-start.sh` passes on the launcher's reason, which names the platform (item 2, `session-names-platform`); the checker refuses a port something else already serves and replies `PORT IN USE` (item 4, checker half). Remains: the tester half of item 4 (it still uses whatever answers on its port; changing that alone would stall a review-loop whose builder left a server running, so it goes with roadmap (c)); item 5, the hook's per-call time on Windows, was not measured. The `readlink -f` claim for macOS before 12.3 is still untested.

- **Severity:** low. **Effort:** S. **Roadmap:** not covered (the roadmap notes everything was
  observed on Linux only, `design-changes.md:720`).
- **Evidence and failure, per item:**
  1. **Windows status is undefined.** `README.md:10` says "Linux or macOS". The launcher handles
     `MINGW*` and `MSYS*` (`scripts/sa-native.sh:13`), CI runs the whole shell suite under Git Bash
     (`.github/workflows/ci.yml:42-60`), and a Windows binary is released. But the install steps
     are `ln -s` (`README.md:18-19`), hooks are invoked as `.sh` files (`hooks/hooks.json:4-15`),
     and no live run on Windows is recorded. A Windows user cannot tell whether it is supported.
  2. **Unsupported platforms lose the gates quietly.** Anything outside the five targets (Windows
     on ARM, Linux on other CPUs, the BSDs) reaches `sa-native.sh:19` and exits 3, and every hook
     then allows everything (C-04).
  3. **`readlink -f`** is used to find the plugin root (`bin/super-agents:5`,
     `scripts/sa-native.sh:7`, `scripts/superagent.sh:17`). To my knowledge BSD `readlink` gained
     `-f` in macOS 12.3; on older macOS it prints nothing, `root` becomes the parent of the current
     directory, and every command fails with a missing-file error. Not tested here; CI runs
     `macos-latest` only.
  4. **Fixed ports.** 3000, 3090 and `3100+NNN` (`templates/review.md:31`) collide with whatever
     the user already runs. The tester then uses the foreign server (`agents/tester.md:13`; C-03),
     and the checker is told to start "the main checkout on port 3000" (`agents/checker.md:11`)
     where the user's own dev server, with real data, may be listening.
  5. **Per-call process cost.** The PreToolUse hook starts a bash process for every Read, Grep,
     Glob, Edit, Write, NotebookEdit and Bash call in every session (`hooks/hooks.json:14`) to
     serve one rarely used agent. The pre-filter exits early (`scripts/block-code-reads.sh:5`), but
     process creation under Git Bash is slow. Not measured.
- **Root cause:** support was added platform by platform through CI, without a stated matrix.
- **Fix:**
  1. `README.md` "Install": a three-row support table (Linux, macOS 12.3 or newer, Windows under
     Git Bash: state "tested in CI, not run live" or "supported", whichever the maintainer decides).
  2. `scripts/session-start.sh:4` already tells the session when sa-core is missing; add the
     platform string in that message when `sa-native.sh` exits 3 for "no prebuilt" so the cause is
     visible.
  3. Keep `readlink -f` and document the macOS minimum. (A portable replacement is a loop of
     `readlink` and `cd`; not worth it unless an older macOS must be supported.)
  4. Ports: `agents/checker.md:11` and `agents/tester.md:13` change to "if the port is already in
     use, stop and report `port in use`" (the tester half is roadmap (c); the checker half is new).
  5. Measure the hook's per-call time on Windows once (`time` around the script with a non-matching
     payload) before deciding anything about the matcher.
- **Alternatives rejected:** narrowing the PreToolUse matcher is not possible by agent type (hook
  matchers select tools; `README.md:115`), and roadmap (d) adds rules to the same hook.
- **Verify:** the README table exists; `bash tests/run.sh` on the three CI systems; a recorded
  timing for item 5.

### N-11 Test gaps that would have caught issues in this register

- **Status: partially fixed.** Added to `tests/run.sh`: prompt tool names against each `tools:` list (it caught `SendMessage` in `agents/teammate.md`, now on its list; whether the agent-teams harness would have supplied it anyway is not verified); frontmatter keys and values; the `.claude` copies compared with the plugin (a drift guard, since N-04 keeps them); the N-01 merger fixture; un-namespaced and near-miss `agent_type` names for both hooks; a fixture with a remote for `commit-tickets` and `drop-specs`, plus `launch-sets-worktree-base`; the released binary asked for its version in `release.yml` (N-09). Remains: model-run evals still cover 2 of 8 skills and no agent (they cost money and were not run or extended).

- **Severity:** low to medium. **Effort:** S each. **Roadmap:** partly (its test lists cover C-01
  to C-11; the items below are additional).
- **Evidence and proposed test, per gap:**

  | Gap | Evidence | Would have caught | Test to add (`tests/run.sh`, consistency section `:467`) |
  |---|---|---|---|
  | Tools an agent's prompt tells it to call are not checked against its `tools:` list | only name and description are checked (`:492-494`) | N-05 (`SendMessage` in `worker.md:35`) | For each `agents/*.md` with a `tools:` line, every backticked name from a fixed list (`SendMessage`, `TaskStop`, `Monitor`, `AskUserQuestion`, `Write`, `Edit`) in the body must be in the list |
  | Frontmatter values are free text | no check of `model`, `effort`, `isolation` | a typo such as `isolation: worktre` silently removes isolation | Each key, when present, must be one of a fixed set |
  | `.claude/` copies | no test reads them | N-04 | The guard described in N-04 |
  | The merger's git recipe | one fixture, H1 (`:452-459`) | N-01 | The fixture described in N-01 |
  | Hook `agent_type` matching | only the namespaced names are fed in (`:521-522`) | N-03 | Un-namespaced and near-miss names for both hooks |
  | No repository with a remote in any fixture | every fixture is `git init` only | C-05 could not be seen | Roadmap `launch-sets-worktree-base`; plus a fixture with `git remote add` for `commit-tickets` and `drop-specs` |
  | The released binary is never the binary under test | `tests/run.sh:10` builds from source; only `shell-windows` installs the published one (`ci.yml:51-58`) | N-09 | In `release.yml` `publish`: run `sa-core --version` from the downloaded Linux asset and compare with the tag |
  | Model-run evals cover 2 of 8 skills and 0 of 11 agents, without Bash | `evals/` has five cases; `README.md:126` | prompt regressions in review-loop, router, worker, merger | Roadmap `evals/review-loop-cannot-self-certify/` and the live smoke; add one case per later prompt change |

- **Root cause:** the suite grew from regressions in the scripts; the prompts' static contracts
  were guarded one grep at a time (`tests/run.sh:476-480`).
- **Verify:** each new check fails on the current tree where the table says an issue exists
  (N-04, N-05) and passes after the fix.

---

## Part 3. Prioritised fix order

Ordering rule: first what can mark work done wrongly or run code unasked with a small fix, then
what stalls or misleads a run, then structure. Items marked (R) are already scheduled by the
roadmap; unmarked items are additions to the named release.

**Batch 1: add to v0.4.1 (all S, no format change)**

1. C-01 (R) arithmetic and grammar fixes.
2. C-05 (R) worktree base; C-06 (R) Stop gate while subagents run. Without these two the parallel
   flow and the loop gate do not do what the README says.
3. N-01 merger approved-file check inverted. One pathspec; closes the widest new hole.
4. N-03 worker gate regex, and N-04 delete the `.claude` copies. Do them together.
5. N-05 `waiting` phase for workers.
6. N-07 one queue slot for merge, check and fix.
7. C-04 (R, items 4-6) and C-10 (R, item 7); C-09 (R, item 8: `MERGE_HEAD`, watchdog dedupe).
8. N-08 steps 1-3 (turn limits, stated rule, total in the plan); N-10 README table;
   N-11 static checks; N-09 release guard.

**Batch 2: v0.5.0 (as the roadmap orders it)**

9. C-08 (R) state store, then C-02 (R) transitions, then C-03 (R) evidence binding, with the
   duplicate-row rule added.
10. N-02 `RD.md` fingerprint. It can ship in v0.4.1 if wanted (S to M, backward compatible); it
    belongs with the transition work because `start` should record both hashes.
11. N-06 router recovery from files, folded into `state.json` (`checked`), and `job await` (N-05).
12. N-08 step 4: per-agent cost in the live smoke.

**Batch 3: v0.6.0**

13. C-11 (R) loop unification; C-07 (R) cut team mode; first-time-user allowlist.
14. N-08 step 5: model changes decided from the smoke's numbers.
15. N-07 alternative (checker in its own worktree), if merge throughput matters by then.

## Part 4. Summary

| ID | Issue | Severity | Effort | Status | Roadmap |
|---|---|---|---|---|---|
| C-01 | Shell arithmetic and prompt text from repo content | high | S | fixed | v0.4.1 item 1 |
| C-02 | `done` not gated; agent owns releases; re-fingerprint | high | M | partially fixed | v0.5.0 steps 3, 5 |
| C-03 | Evidence not bound to code; self-certified results; first row wins | high | L | partially fixed | v0.5.0 steps 4, 7 |
| C-04 | Gates fail open; trust agent-written `dir`; launcher | high | S-M | partially fixed | v0.4.1 items 4-6; v0.5.0 step 5 |
| C-05 | Worktrees start from the remote default branch | high | S | fixed | v0.4.1 item 2 |
| C-06 | Stop gate spends its blocks on waits | high | S | fixed | v0.4.1 item 3 |
| C-07 | Team mode bypasses isolation and the gate | medium | M | skipped | v0.6.0 item 2 |
| C-08 | Runtime status in tracked files in the main checkout | medium | M | open | v0.5.0 step 1 |
| C-09 | Recovery contradictions; watchdog repeats; `MERGE_HEAD` | medium | S-M | partially fixed | v0.4.1 item 8; v0.5.0; v0.6.0 |
| C-10 | Over-powered reviewer, builder, watchdog, checker | medium | S | partially fixed | v0.4.1 item 7; v0.5.0 step 6 |
| C-11 | Three loops; shell parser; Python compatibility; `specs/*` | low-medium | M | partially fixed | v0.4.1 item 9; v0.6.0 |
| N-01 | Branch may change other tickets' evals and `review.md` | high | S | new, probed | not covered |
| N-02 | `RD.md` approved but not fingerprinted | medium | S-M | fixed | not covered |
| N-03 | Worker gate matches one exact agent name | medium | S | skipped | not covered |
| N-04 | `.claude` copies duplicate and shadow the plugin | medium | S | skipped | not covered |
| N-05 | Worker that asks the user is blocked; no `SendMessage` | medium | S | fixed | partly (b) |
| N-06 | Router single point of failure; state in context only | medium | M | partially fixed | partly (g), (e) |
| N-07 | Checker races the next merge; reproducers share a port | medium | S | fixed | not covered |
| N-08 | Models, effort, turn limits without a rule or ceiling | medium | S-M | partially fixed | not covered |
| N-09 | Release not tied to the source of its binaries | low-medium | S | fixed | not covered |
| N-10 | Portability: Windows status, platforms, ports, `readlink` | low | S | partially fixed | not covered |
| N-11 | Test gaps (tool lists, frontmatter, remotes, released binary) | low-medium | S | partially fixed | partly |

22 issues: 11 carried over (6 high, 4 medium, 1 low-medium) and 11 new (1 high, 7 medium,
2 low-medium, 1 low).

## Not verified for this document

- No live agent run was made. N-06 and N-07 are derived from reading the prompts; their scenarios
  were not reproduced with real agents.
- Whether the agent-teams harness gives teammates messaging tools beyond their `tools:` list (N-05).
- Whether the router's Glob returns git-ignored `.job/` files (N-06).
- Which model versions the `opus` and `sonnet` aliases resolve to, and the prices in N-08, which
  come from a reference cached on 2026-11-03, not from a live lookup.
- Whether `claude plugin eval .` loads the repository's `.claude/` directory (N-04, item 5).
- The `readlink -f` behaviour on macOS before 12.3 (N-10) is from memory, not from a test.
- The `agent_type` prefix under the `@skills-dir` install (N-03), still open from the review.
- Whether release v0.4.0 was published (N-09 note). Git state was only read, never changed.
- `docs/superpowers/plans/2026-11-07-sa-core.md` was not read; `core/tests/*.rs` were read by test
  name only.
