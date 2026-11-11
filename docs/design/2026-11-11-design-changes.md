# super-agents: design changes and roadmap

Design only. Nothing in the repo was edited. Builds on the review of `release/v0.4.0` (commit `c3810c1`).

**Revision 2, after testing.** The review findings were reproduced with saved scripts, and the harness assumptions were tested in 8 headless runs against copies of the plugin in throwaway repositories (Claude Code 2.1.322). Every assumption below is now marked **Verified** or **Refuted** with a pointer into `evidence/` (the folder next to this file; `evidence/INDEX.txt` lists it). Each section that a result changed has a "Changed after testing" note. The appendix has the result tables, three things that contradict my earlier review or design, and two side effects of the testing.
All paths are relative to `/home/orneyfish/Projects/super-agents/`. "Probed" means I ran the real script against a scratch fixture during the review; "unverified" means I read no proof of it in this repo.

Threat model used throughout: the system defends against a **lazy, confused or prompt-injected agent** and against **hostile repository content**. It does not defend against an agent that deliberately forges files with Bash under the same user account; README.md:113 already says to use a container for that. Where a control is only nudge-strength, this document says so.

---

## 1. Design principles

1. **Repo content and agent-written files are data, never code.** Every value a hook or script reads is matched against a closed grammar and is never expanded, evaluated or echoed into a prompt unvalidated.
2. **A status transition is performed by one mechanism (`sa-core`) that checks its own preconditions.** Hooks only catch a turn that ends early; releasing a hook never produces `done`.
3. **A pass counts only for the code it ran against.** Verdicts carry the tested tree id, are written by the tester (not the builder or orchestrator), and the final verdict is taken on the merged tree.
4. **A control that cannot decide refuses, and says so.** The only control on a path fails closed; a nudge fails loud. Nothing fails silent.
5. **An agent's tool list is an allowlist sized to its role.** "Read-only" in prose is not a control and is not claimed as one.
6. **One definition per mechanism:** one loop, one status store, one parser for gate inputs.

---

## 2. Target design

### (a) Input hardening

**Current behaviour**
- `scripts/eval-gate.sh:12` reads `state.md` keys with `sed`; `:24-28` feeds `gate_blocks` raw into `$((n+1))`. Reproduced: `gate_blocks: x[$(touch F)]` in `state.md` created `F` at the first Stop, also from a fresh clone of a repository that tracks the file (`evidence/A-repro.out`, A1 and A1b).
- `scripts/worker-gate.sh:15-17` does the same with `.job/gate_blocks` (reproduced, A2; the review had only inferred this one); `:12` trusts `dir` from the worker's own `status.json` (reproduced, A5: a directory outside the repo with a self-written fingerprint passes).
- `scripts/session-start.sh:15` copies `dir:` and `round:` text into every session's context without validation.
- `scripts/job-status.sh:6-7` builds a file name from an unchecked `--name`.
- `core/src/scan.rs:108-111` prints the worker's free-text `note` into a `PROBLEM` line the watchdog and router read; `core/src/http.rs:10-12` probes any `http://` host named in `watchdog.conf`.
- `.gitignore` entries (`scripts/init-project.sh:31`) do not stop a repository from shipping tracked `.super-agents/` or `.job/` files.

**Target**

*Tracked-file rule.* A runtime file (`.super-agents/**`, `.job/**`) is ignored when any of these holds: it is tracked by git, it is a symlink, or its parent directory is a symlink. "Ignored" means the gate behaves as if no loop exists and emits one fixed message containing no repo-derived text. Rationale: a gate armed by repository content is not a gate the user started, so this is input rejection, not fail-open.

```bash
# v0.4.1 shell form (replaced by sa-core parsing in v0.5.0)
untrusted() { [ -L "$1" ] || [ -L "$(dirname "$1")" ] || git -C "$cwd" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }
int()       { [[ $1 =~ ^[0-9]{1,3}$ ]] && printf %s "$((10#$1))" || printf 0; }   # garbage counts as 0, so the gate blocks rather than releases
```

*Accepted grammar.* Anything else makes the key "absent"; an absent load-bearing key means "no valid loop" plus a message.

| File | Key | Accepted |
|---|---|---|
| `state.md` | `dir` | `^[A-Za-z0-9._/-]{1,200}$`, no `..`, relative, and its realpath is under `<toplevel>/specs/` |
| | `session` | `^[A-Za-z0-9-]{8,64}$` |
| | `active`, `awaiting_user` | exactly `true` or `false` |
| | `round`, `max_rounds`, `gate_blocks` | `^[0-9]{1,3}$` |
| | `base`, `checkpoint` | `^[0-9a-f]{7,64}$` |
| | `risk` | `low`, `medium`, `high` |
| `.job/status*.json` | `ticket` | `^[0-9]{3}$` |
| | `phase` | `building`, `testing`, `reviewing`, `done`, `blocked` |
| | `dir` | **not read by the gate**; the ticket folder is resolved as the single `specs/tickets/NNN-*` under the hook cwd's toplevel |
| | `agent` / `--name` | `^[A-Za-z0-9._-]{1,64}$` |
| | `note` | at most 200 chars, control characters removed, printed only after a ` :: ` separator |
| `.job/gate_blocks` | whole file | `^[0-9]{1,3}$` |
| `watchdog.conf` | `ignore` | `^[0-9]{3}(,[0-9]{3})*$` |
| | `app_url` | `http://` to `localhost`, `127.0.0.1` or `[::1]` only |

`session-start.sh` reuses the `dir` and `round` grammar before building its context line.

**Files that change:** `scripts/eval-gate.sh`, `scripts/worker-gate.sh`, `scripts/session-start.sh`, `scripts/job-status.sh`, `core/src/scan.rs`, `core/src/http.rs`.

**Migration:** none. Valid existing files already match the grammar. A project that committed `.super-agents/` by mistake gets the fixed message and must `git rm --cached` it.

**Rejected alternatives**
- *Quote the arithmetic only (`$(( ${n:-0} + 1 ))`).* Still evaluates the string; validation is the fix.
- *Block when `state.md` is tracked.* Lets a hostile repo wedge any session three times and puts its text in front of the model.
- *Keep trusting `dir` but require it inside the repo.* The worker can still point it at another ticket; resolving from the ticket number removes the field from the trust path.

---

### (b) Transition gating

**Current behaviour**
- `core/src/board.rs:243-246` accepts any status from any status; `:274-278` rewrites the fingerprint on every `ready`, so edited evals can be re-approved by any agent with Bash.
- `skills/review-loop/SKILL.md:63` sets `active: false` as the first Finish step and `eval-gate.sh:13` exits when `active` is not `true`, so the normal Done path is never checked (probed).
- The gated agent owns every release: `awaiting_user` (`eval-gate.sh:14`, advertised at `:32`), the counter it resets itself (`SKILL.md:40`), `.job/gate_blocks` (probed), `blocked` phase (`worker-gate.sh:13`).
- Dependencies (`waits for`) are enforced only by router prose (`agents/router.md:31`).
- **Seen live** (`evidence/live/run5-review-loop/timeline.txt`, `eval-gate-exits.txt`): the orchestrator's subagents ran in the background, so its turn ended, and the Stop hook fired, at every wait. The gate blocked three times in the first 12 seconds while the builder was still starting, then printed "released after 3 blocks" for the rest of the round. At the sixth Stop it passed silently while `results.md` still said `**Review:** pending`. At the seventh, `active: false` (set by the orchestrator with `sed`) made it exit without evaluating. The run itself was honest: the orchestrator ran `check-evals --passed` on its own before finishing.
- In a repository that has a remote, a worktree-isolated agent starts from the remote's default branch, not from the local integration branch (`evidence/live/run1-main-probe`: HEAD was `origin/main`, two commits behind the checked-out branch). Tickets committed only on the local integration branch (`README.md:51`) are then missing from the worker's worktree. Not tested with the real worker; tested with a probe agent that has the same `isolation: worktree`.

**Target state machine** (one per ticket or feature directory)

```
draft --approve--> ready --start--> building --finish--> done
  ^                  |                 |                   |
  +----unapprove-----+                 +--reset--> ready   +--reopen--> building
```

| Edge | Command | Intended caller | Preconditions checked by sa-core | Effects |
|---|---|---|---|---|
| draft -> ready | `board set X ready` | the user's session (`mark-ready`, or `write-eval` step 7) | current status is `draft`; structure check passes (today prose at `skills/mark-ready/SKILL.md:11`) | writes `.evals.sha256`; log entry |
| ready -> draft | `board set X draft` | the user's session | current status is `ready` | removes the fingerprint |
| ready -> building | `loop start X` (session) or `job start NNN` (worker) | orchestrator, worker | status `ready`; `evals.md` matches the fingerprint; every `waits for` ticket is `done`; for a worker, the ticket folder exists in its worktree and the main checkout's HEAD is an ancestor of the worktree's HEAD | records base sha, worktree, owner, start time, and a copy of the approved fingerprint |
| building -> done | `loop finish X` (session) or `board set NNN done` (merger) | orchestrator, merger | `verify --passed` (section c) passes on the current tree; no `MERGE_HEAD` | writes `done` to `RD.md` and the board row; clears loop fields |
| building -> ready | `board set X ready --reset` | user, or a merger asked by the router | `evals.md` still matches the recorded fingerprint | **does not re-fingerprint**; clears results |
| done -> building | `board set X building --reopen` | user | none | log entry |

Rules that close the review's findings:
- The fingerprint is written on exactly one edge (draft -> ready). Every later edge verifies against the copy recorded at `start`, so "edit evals, set ready, set building" no longer launders a change.
- `done` is reachable only through `verify --passed`. There is no flag to skip it.
- Every transition appends one line to `.super-agents/state.log` (time, from, to, caller agent type if known). Final reports print the count of approvals after the first.

**Who may trigger an edge** is enforced at three strengths, stated honestly:
1. *Preconditions in sa-core* (mechanical; strong).
2. *PreToolUse caller rule* (section d): Bash commands containing `board set … ready`, `board set … draft`, `--reopen` or `--reset` are denied for subagents, recognised by the `agent_id` field in the payload. Regex on a command string, so nudge-strength.
3. *The log* (detective).

**What the hooks do, versus `board set`**

| Mechanism | Today | Target |
|---|---|---|
| `board set` / `loop finish` / `job done` | no checks | the only way to change status; checks the table above; exit 1 with `FAIL:` lines otherwise |
| Stop hook | runs `check-evals --passed` while `active: true` | **first: if the payload's `background_tasks` lists a running task, allow silently** (the session is waiting for a subagent, not finishing). Otherwise, if this session owns a loop that is `building` and not awaiting the user: block with "the loop is not finished: run `super-agents loop finish`, `loop await \"<question>\"` or `loop stop`". At most 3 consecutive blocks, counter owned by sa-core and reset by `loop round`. Does not evaluate evals itself. |
| Stop hook, on release or allow | silent | when the session owns a loop that is not `done`, emits `systemMessage`: "`<dir>`: status building, P/T evals passing at tree `<id>`". The user hears the gate's verdict from the gate, not from the agent. |
| SubagentStop hook | runs `check-evals --passed` for workers | block if this worker's record has a phase other than `done` or `blocked` (3-block cap). `done` is set only by `job done`, which runs `verify --passed`. |
| `loop await` / `loop resume` | agent edits `awaiting_user` | same effect, through sa-core; cannot produce `done` |
| `loop stop` | agent sets `active: false` | ends the loop **unfinished**; status stays `building` |

**Interface sketch**

```
super-agents loop start <dir>            # ready -> building, binds this session
super-agents loop round                  # round += 1, resets the block counter; refuses past max_rounds
super-agents loop await "<question>" | loop resume
super-agents loop finish <dir>           # building -> done, or exit 1 with FAIL lines
super-agents loop stop <dir>             # unfinished; status stays building
super-agents job start <NNN> | job beat <phase> [note] | job done | job blocked "<why>"
```

`super-agents board set` and `super-agents job-status` keep working as wrappers, so existing prompts do not break mid-migration.

**Files that change:** `core/src/board.rs` (edges), new `core/src/state.rs` and `core/src/verify.rs`, `core/src/main.rs`, `bin/super-agents`, `scripts/eval-gate.sh` and `scripts/worker-gate.sh` (become two-line calls to `sa-core hook stop|subagent-stop`), `scripts/job-status.sh` (wrapper), `skills/review-loop/SKILL.md`, `skills/mark-ready/SKILL.md`, `skills/write-eval/SKILL.md`, `agents/worker.md`, `agents/merger.md`, `agents/router.md`.

**Migration**
- `super-agents loop adopt <dir>` imports `dir`, `base`, `checkpoint` and `round` from a legacy `state.md` (validated by the grammar in (a)) and requires a fresh tester run. Supported for one release.
- `super-agents board migrate` copies statuses from `BOARD.md` into the runtime store. A ticket that was `building` becomes `building` with no worker, which the watchdog reports; the user restarts it.
- Tickets approved before this release keep their `.evals.sha256`; no re-approval.

**Assumptions, now tested**
- *SubagentStop's `cwd` is the worker's worktree.* **Verified** (`evidence/live/run1-main-probe/hooklog-summary.txt`; and with the plugin's real `worker-gate.sh` against a stub worker, which was blocked three times and then released, `evidence/live/run7-worker-gate`).
- *`session_id` is stable across resume.* **Verified** for `--resume` (`evidence/live/run2-resume-baseref-head`: same id, `source: resume`). Not tested: compaction, `--continue`, `--fork-session` (the last one creates a new id by design). `loop resume` stays as the explicit rebind.
- *`systemMessage` is shown.* **Verified** in the output stream, where it appears as a notice "Stop says: …" (`evidence/live/run5-review-loop/stream.jsonl`). How the interactive UI renders it was not looked at.
- *A Stop means the agent is finishing.* **Refuted** (see "Seen live" above). The Stop payload carries `background_tasks` and `stop_hook_active` (`evidence/live/run5-review-loop/hooklog-summary.txt`, key list), which is what the new first rule uses.
- *Worktrees start from the local HEAD.* **Refuted when the repository has a remote** (`run1`: started from `origin/main`); **verified when it has none** (`run3`: started from the checked-out branch, not from local `main`); **verified with the setting `worktree.baseRef: "head"`** (`run2`, `run8`; the setting's text is in `evidence/B4-baseRef-binary-strings.txt`).

**Changed after testing**
- The Stop hook's first rule (allow while a background task runs) is new. Without it the redesigned hook would repeat what the current one did live: spend its blocks on waits.
- `scripts/superagent.sh` must start the router with `--settings '{"worktree":{"baseRef":"head"}}'`, and `job start` checks ancestry so that a worker started from the wrong base fails at once instead of building without its ticket. Both are in v0.4.1.
- The review-loop text tells the orchestrator to start each subagent in the foreground (`run_in_background: false`); main-thread Agent calls without it ran in the background (`run5`), while subagents' own Agent calls were synchronous (`run1`, `run3`).
- "Subagent" in the caller rule means "the payload has `agent_id`", not "`agent_type` is set": in a session started with `--agent`, the main thread's payloads carry `agent_type` too (`evidence/live/run3-router-allowlist/hooklog-summary.txt`).

**Rejected alternatives**
- *Keep the check in the Stop hook and just move `active: false` later.* The gated agent still owns the flag.
- *Remove the 3-block cap.* A wedged session is worse than a released one, provided release is not `done`.
- *Authenticate the user for `ready`.* Not possible under one account; see open decision 2 for the terminal-only variant.

---

### (c) Evidence binding

**Current behaviour**
- `scripts/check-evals.sh:59-66` accepts a `pass` cell plus any non-empty file; no binding to code, time or run; the `**Review:**` line is never read.
- `results.md` is written by the worker (`agents/worker.md:21`) or the orchestrator (`skills/review-loop/SKILL.md:42`), not the tester (`agents/tester.md:16` forbids it).
- After review fixes the worker re-tests "the failing evals and their neighbours" (`worker.md:20`).
- The tester uses whatever answers on the port (`tester.md:13`).
- The merger runs lint and build only, including after hand-resolved conflicts (`agents/merger.md:16-17`); fix branches merge on the reproducer's word (`agents/router.md:49`).
- The router accepts `findings-fixed` (`router.md:46`), which nothing defines.
- **Seen live** (`evidence/live/run5-review-loop/main-and-reviewer-commands.txt`, `evidence/live/C-artifacts/after-review-loop/`): the tester ran all seven evals, in one Bash call, inside a temporary copy of the working tree, and wrote one evidence file per eval. The files hold output only, not the command (`tester.md:14` asks for both); the smallest is 16 bytes. The orchestrator wrote `results.md` with a shell heredoc and set `**Review:** clean` with `sed`. The reviewer ran two Bash commands and wrote nothing in the repository.
- **Seen live:** nobody used the Edit or Write tool in the whole flow. The builder changed the source through Bash (a Python heredoc), and the orchestrator wrote `state.md` and `results.md` through Bash.

**Tree id.** The identity of "the code that was tested", independent of commits:

```
sa-core tree-id <dir>
  # temp index: read-tree HEAD (or --empty), then: git add -A -- . ':(exclude)specs/tickets' ':(exclude)<dir>'
  # then: git write-tree            -> 40-hex tree id
```

It honours `.gitignore`, includes new untracked source files (the reviewer already needs those, `agents/reviewer.md:15`), is unchanged by a checkpoint commit, and changes on any source edit. `Dirty` is informational: whether the id differs from HEAD's tree under the same exclusions.

Measured (`evidence/B10-tree-id.out`): on a synthetic repository of 60,000 files (235 MB) the id took 636 ms when the index was rebuilt from HEAD and **47 ms when the repository's own index was copied first** (89 ms after editing 10 files and adding 5); on the largest real repository under `~/Projects` (543 tracked files, 2.7 GB working tree) 66 ms and 9 ms. The id was identical before and after committing the same content. So sa-core copies the index into a temp file, and writes new objects to its own directory under `.super-agents/` with the repository's object store as an alternate. No repository on this machine was large enough to measure a truly big monorepo.

**`results.md` format v2** (machine-written; humans still read it as a table)

```
# Results: 003-profile
<!-- results v2; written by `super-agents result`; do not edit -->
**Run:** 2026-11-12T09:14:03Z
**Tree:** 3f2a9c1e5b...   **Head:** 9ab01c7   **Dirty:** yes
**Review:** clean @ 3f2a9c1e5b...
| eval | result | runs | evidence | sha256 | at |
|------|--------|------|----------|--------|----|
| E1 | pass | 1/1 | evidence/E1-signup.png | 9d2702c9... | 2026-11-12T09:14:40Z |
| E2 | fail | 0/1 | - | - | 2026-11-12T09:15:02Z |
```

A failing row's observation goes in a `<!-- E2: expected 400, got 200 -->` line under the table, so the table stays parseable.

**Who writes it: the tester only, through the CLI**

```
super-agents result begin <dir>                                  # stamps Run and Tree, drops old rows
super-agents result add <dir> E1 pass evidence/E1-signup.png
super-agents result add <dir> E2 fail "expected 400, got 200"
super-agents result end <dir>                                    # refuses if an eval has no row; prints P/T passing
super-agents verdict <dir> clean | findings <n> | rethink        # reviewer; stamps the tree id
```

- `result add … pass` requires the evidence file to exist, be non-empty and sit under `<dir>/evidence/`; it records the file's sha256. It refuses if the tree id changed since `begin` (the code moved mid-run).
- Timestamps come from sa-core's clock, which retires the prose rule at `worker.md:24` ("never a made-up time").
- **The authoritative record is sa-core's own file, `.super-agents/results/<item>.json`; `results.md` is a rendered copy for people.** `verify` reads the record, so a `results.md` written by hand, which is what the orchestrator did live, has no effect.
- `super-agents result exec <dir> E3 -- <command>` runs a command-type check itself and stores the command, its output and its exit code as the evidence file. The tester still gives the verdict with `result add`. This fixes evidence that shows output without the command.
- Caller restriction (`result` for the tester, `verdict` for the reviewer) is the PreToolUse rule in (d): a match on the Bash command for a given `agent_type`. That a hook can deny by `agent_type` from the payload alone is verified (`evidence/live/run1-main-probe`, step 8). Still nudge-strength: the record is a file.
- The tester starts the app itself and stops it afterwards. "If something answers on the given port, use it" (`tester.md:13`) is removed; a busy port is `fail` with "port in use". The tester may run the checks in a copy of the tree, as it did live; the binding is by content, because `result add` re-computes the tree id of the real tree and refuses if it moved since `begin`.

**How the gate verifies (`sa-core verify <dir> --passed`)**
1. `evals.md` matches the fingerprint recorded at `start` (for tickets also the main checkout's copy, as `check-evals.sh:44-48` does today).
2. A results record exists for the item and its run time is later than the loop's or job's start time (results from an earlier attempt do not count).
3. `**Tree:**` equals `tree-id` computed now. Otherwise: `FAIL: results are for tree X, the code is now Y; rerun the tester`, followed by the changed paths (`git diff-tree --name-only X Y`).
4. Every eval in `evals.md` has a `pass` row; each evidence file exists and matches its recorded sha256.
5. `**Review:**` is `clean @ <the same tree>`.

**After a review-fix round.** Any edit changes the tree id, so both the tester's rows and the reviewer's verdict are stale by construction. The loop therefore runs the full eval set each round (as the review-loop already does, `SKILL.md:42`) and takes a review of the fix diff (`reviewer.md:16`). A worker may ask the tester for a subset during a round for fast feedback (`result begin --only E2,E3` marks the run partial); a partial run never satisfies `verify`. `findings-fixed` disappears.

**Merged-tree test before the merge commit** (merger, replacing steps 3-5 of `agents/merger.md`)

```
0. MERGE_HEAD present?  -> git merge --abort, report it, continue          (section g)
1-2. tree and approved-file checks, as today
3. git merge --no-ff --no-commit $SHA      (conflicts: resolve or abort, as today)
4. lint, build and the project's test command (review.md "How to test this project")
5. spawn super-agents:tester on the ticket folder in the main checkout, ticket port 3100+NNN
6. spawn super-agents:reviewer only if step 3 resolved conflicts by hand (scope: the conflicted files)
7. any failure in 4-6 -> git merge --abort, report
8. git commit; then `super-agents board set NNN done`, which runs verify on the committed tree
```

The tree id of the staged merge equals the tree id after the commit (the exclusions hide `specs/tickets`), so step 8 passes exactly when step 5 tested what was committed. The worker's own pre-merge results become fast feedback; the merged-tree run is the authoritative one, and it is spawned by an agent that did not build the ticket.

Fix branches use the same steps with `fix <branch> for NNN`: the tester runs ticket NNN's evals plus the project tests, which now include the reproducer's regression test.

**Files that change:** new `core/src/results.rs`, `core/src/treeid.rs`, `core/src/verify.rs`; `scripts/check-evals.sh` (becomes a wrapper keeping its flags and `OK:`/`FAIL:` output, which `mark-ready/SKILL.md:11` and `write-eval/SKILL.md:20` rely on); `agents/tester.md`, `agents/reviewer.md`, `agents/worker.md`, `agents/merger.md`, `agents/router.md`, `skills/review-loop/SKILL.md`, `templates/evals.md`, `README.md`.

**Migration:** a v1 `results.md` fails check 2 with "results are in the old format; rerun the tester". No conversion: old rows carry no tree id, so converting would manufacture proof.

**Assumptions, now tested**
- *A nested subagent works in its spawner's directory.* **Verified**: a leaf started by a worktree agent reported the worktree as its `pwd` (`evidence/live/run1-main-probe`, step 11).
- *`super-agents` commands run from inside a worktree and reach the main checkout.* **Verified**: `board root` printed the main checkout (`run8`, step 10), and `board set 001 building` run by a worktree agent changed `BOARD.md` and `RD.md` in the main checkout (`evidence/live/run7-worker-gate`; this is also the review's P6, now seen live). Plain `git -C <other dir>` and `cd <dir> && git …` are refused for a worktree-isolated agent (`run8`, steps 8, 9, 13), so sa-core, not the agent, must be the one to call git across checkouts.
- *The merger may spawn the tester.* **Verified** that a subagent can start another one, to depth 3 under a `--agent` main thread (`run1`, `run3`). **Refuted** that a subagent's own `Agent(x)` list restricts it: a probe with `Agent(probe-leaf)` started `probe-leaf2` (`run1`). In a router session the router's list is what binds everyone (`run3`), and the tester is already on it (`router.md:4`). So the merger needs the plain `Agent` tool; no two-phase merger is needed.

**Changed after testing**
- The authoritative results record and `result exec` are new; revision 1 relied on denying Edit and Write on `results.md`, which would have matched nothing in the live run.
- The tree id uses a copied index (47 ms instead of 636 ms on 60,000 files).
- "The tester starts the app from the directory it stamps" is dropped as a requirement; content binding replaces it.

**Rejected alternatives**
- *Bind to the HEAD commit sha.* The review-loop tests before anything is committed (`reviewer.md:15`), and a checkpoint commit would invalidate valid results.
- *Per-row tree ids so unaffected passes survive a fix.* Needs an eval-to-file dependency model; a wrong one gives false passes.
- *Signed results (HMAC).* The key would be readable by the same user the agents run as.
- *Have the gate inspect evidence content with a model.* A non-deterministic gate; the independent merged-tree run is the check.
- *Let the router spawn the tester on the worker's branch before merging.* Tests the wrong tree; the merged tree is what lands.

---

### (d) Agent power

**Tools, today and proposed**

| Agent | Today (file:line) | Proposed |
|---|---|---|
| router | Read, Grep, Glob, Agent(8 types), SendMessage, TaskStop, AskUserQuestion (`router.md:4`) | unchanged |
| worker | Read, Grep, Glob, Bash, Edit, Write, Agent, Monitor, TodoWrite (`worker.md:4`) | unchanged. A scoped `Agent(...)` list on a subagent is not enforced (tested); under the router, the router's own list already limits every agent to its eight types (tested) |
| teammate | same as worker (`teammate.md:4`) | removed with team mode (f) |
| builder | no `tools` line: every tool and MCP connector in the session (`builder.md:1-5`) | Read, Grep, Glob, Bash, Edit, Write, TodoWrite |
| reviewer | everything except Edit, Write, NotebookEdit (`reviewer.md:4`) | Read, Grep, Glob, Bash, ToolSearch, `mcp__claude-in-chrome__*` |
| tester | Read, Grep, Glob, Bash, ToolSearch, chrome (`tester.md:4`) | unchanged |
| merger | Read, Grep, Glob, Bash, Edit (`merger.md:4`) | add `Agent` (the tester and reviewer are on the router's list, which is what binds it) |
| checker | Read, Grep, Glob, Bash, ToolSearch, chrome (`checker.md:4`) | unchanged; description stops saying "read-only" |
| reproducer | Read, Grep, Glob, Bash, Edit, Write, ToolSearch, chrome (`reproducer.md:4`) | unchanged |
| watchdog | Read, Grep, Glob, Bash, Edit, Monitor, SendMessage, TaskStop (`watchdog.md:4`) | drop Edit; rule changes go through `super-agents watchdog set <key> <value>`, validated by the grammar in (a) |
| first-time-user | Bash, ToolSearch, chrome (`first-time-user.md:4`) | unchanged in v0.4.1; Bash moves to an allowlist in v0.6.0 (section 3) |

What testing showed about these lists (`evidence/live/run6-tool-lists`, `run1-main-probe`, `run3-router-allowlist`):
- A subagent's `tools:` allowlist **is enforced**: an agent with `tools: Read` had no Bash, Write or Agent tool.
- The reviewer's form, `disallowedTools: Edit, Write, NotebookEdit`, leaves it Agent, Bash, Skill and, loadable on demand, WebFetch, WebSearch, SendMessage, Monitor, the cron and remote-trigger tools and more. The probe wrote a file with Bash and started another agent. (MCP connectors were switched off in the test sessions, so their inheritance was not observed.)
- `router.md:21` is right: the `Agent(...)` list of a `--agent` main thread binds every descendant. A middle agent with an unrestricted `Agent` tool got "Agent type … not found. Available agents:" followed by exactly the router's list.
- A scoped `Agent(...)` list on a subagent in an ordinary session is **not** enforced. So in the single-feature flow the only way to keep the builder and reviewer from starting agents is to leave `Agent` out of their `tools`, which the table does.

**PreToolUse deny rules for approved files** (new `sa-core hook pre-tool`, called from one script so each tool call still costs one process)

| # | Matches | Denied for | Reason given |
|---|---|---|---|
| 1 | Edit, Write, NotebookEdit on `evals.md`, `RD.md`, `mockup.html` or `.evals.sha256` inside a spec directory whose status is `ready`, `building` or `done` | every agent, the main session included | "approved file; the user re-opens it with `super-agents board set <dir> draft`" |
| 2 | Edit, Write on any `results.md` under `specs/` | everyone | "written only by `super-agents result`" |
| 3 | Edit, Write under `.super-agents/` or `.job/` | everyone | "runtime state; use the `super-agents` commands" |
| 4 | Bash containing `super-agents result ` | every agent type except `super-agents:tester` | "only the tester records results" |
| 5 | Bash containing `super-agents verdict ` | every agent type except `super-agents:reviewer` | "only the reviewer records a verdict" |
| 6 | Bash containing `board set` with `ready`, `draft`, `--reopen` or `--reset` | every subagent (the payload has `agent_id`) | "approval is the user's step" |

**Coverage, measured.** In the live single-feature run there were 0 Edit and 0 Write calls: every file change went through Bash (`evidence/live/run5-review-loop/hooklog-summary.txt`). Rules 1-3 would have matched nothing. They stay because they are cheap and catch the direct case, but nothing in this design depends on them: approved files are protected by the recorded fingerprint, results by the sa-core record, and status by the transition checks. Rules 4-6 match Bash commands, which is where the live traffic was.

NotebookEdit carries `tool_input.notebook_path`, not `file_path`, and is loaded on demand through ToolSearch in this version (`evidence/live/run1-main-probe/hooklog-summary.txt`).

Exceptions:
- Status `draft`: everything is editable, which is where `write-eval`, `write-tickets` and `classify-risk` (`skills/classify-risk/SKILL.md:15`) do their writing.
- The `**Status:**` line and the board row are written by sa-core, not by the Edit tool, so rule 1 never blocks a transition.
- `--reset` asked for by the router runs in the merger: rule 6 allows agent type `super-agents:merger` for `--reset` only.
- Writes through Bash to the approved files are **not** pattern-matched. Detection stays where it is deterministic: the recorded fingerprint (b) and the merger's `git diff` of approved files (`merger.md:15`).

**Assumptions, now tested**
- *`agent_type` is set on subagent tool calls, as `<plugin>:<agent>`.* **Verified** (`super-agents:probe-worker`; `run1`).
- *`agent_type` is empty in the main session.* **Verified for an ordinary session** (the key is absent; `run1`) and **refuted for a session started with `--agent`**: there the main thread's payloads carry the agent's type (`super-agents:probe-router`; `run3`). The reliable test for "this is a subagent" is the `agent_id` key, present on all 191 subagent payloads and absent on all 115 main-thread ones across the eight runs (`evidence/live/agent_id-check.txt`).
- *Edit and Write carry `tool_input.file_path`.* **Verified** (`run1`). NotebookEdit: `notebook_path`.
- *A PreToolUse hook can deny one agent type from the payload alone.* **Verified**: a Write to `protected.txt` was refused for `probe-worker` ("PreToolUse:Write hook error: PROBE_DENY…") and allowed for the main session, using the plugin's own `hookio emit deny` (`run1`, repeated in `run2` and `run3`; hook at `evidence/hooks/probe-deny.sh`).

**Changed after testing**
- Worker and merger rows: scoped `Agent(...)` lists removed, because they do not restrict a subagent.
- Rule 6 and every "is this a subagent" test use `agent_id`.
- Rules 1-3 are demoted from a control to a convenience, with the coverage note above.

**Files that change:** all `agents/*.md` frontmatter listed above, `hooks/hooks.json` (matcher gains nothing new; the same script dispatches), `scripts/block-code-reads.sh` (keeps the first-time-user rules until v0.6.0), `core/src/main.rs`, new `core/src/pretool.rs`, `README.md:73-82`.

**Migration:** none for state. Behavioural: the reviewer and builder lose MCP connectors, web tools and the Agent tool.

**Rejected alternatives**
- *Keep `disallowedTools` and add more names.* A denylist grows with every connector the user installs.
- *Pattern-match Bash writes to `evals.md`.* The first-time-user parser (`block-code-reads.sh`, 140 lines) shows where that road ends; probed bypasses needed no trickery.
- *A separate hook script per rule.* One more process per tool call each.

---

### (e) Loop unification

**Current behaviour:** three loop definitions with different rules.

| | `skills/review-loop/SKILL.md` | `agents/worker.md` | `agents/teammate.md` |
|---|---|---|---|
| Rounds | 5 (`:57`) | 3 fix rounds (`:20`) | 3 (`:15`) |
| Done | all evals pass and review `clean` (`:55`) | router accepts `clean` or `findings-fixed` (`router.md:46`) | integrator's report |
| Re-test after fixes | every eval, every round (`:42`) | failing evals and neighbours (`:20`) | unspecified |
| Stuck rule | same class and location after two rounds (`:56`) | none; router counts its own rounds (`router.md:47`) | none |
| Results written by | orchestrator (`:42`) | worker (`:21`) | integrator (`:15`) |

**Target: one definition, `templates/loop.md`**, printed by `super-agents template loop.md` (the command exists, `bin/super-agents:22-23`). The skill and the worker both start with "run `super-agents template loop.md` and follow it".

```
Parameters: DIR, BUILDER (a `super-agents:builder` subagent in a session; yourself in a worker), PORT, ACCOUNT
Start:    super-agents loop start DIR      (worker: super-agents job start NNN)
Round N (1..5):
  1. super-agents loop round
  2. Build   - BUILDER. Rules that live here once: stay inside Touches, never edit the contract files,
               fix the whole class of a finding, RETHINK from round 3.
  3. Test    - spawn super-agents:tester (full eval set). It writes results.md.
  4. Review  - spawn super-agents:reviewer (round 1: diff since base; later: since checkpoint). It records its verdict.
  5. Checkpoint commit unless a previously passing eval regressed.
  6. Decide  - Done:  `super-agents loop finish DIR` exits 0.
               Stuck: same class and location open after two fix rounds. Stop, report.
               Flaky: section (g).
               Cap:   N = 5. Stop, report.
Finish:   report rounds, P/T, open findings, branch. Unfinished -> `super-agents loop stop DIR`.
```

Single clean criterion: `loop finish` succeeds, that is, every eval passes and the review verdict is `clean`, both at the current tree, with the approved evals unchanged. "Clean" keeps its risk threshold (`agents/reviewer.md:19`).

**Reuse**
- `skills/review-loop/SKILL.md` shrinks to preconditions (branch, `--ready`), the harness note, and "follow the template with BUILDER = subagent".
- `agents/worker.md` shrinks to its worktree and git rules (`:11-13`), "follow the template with BUILDER = yourself", commit, and the reply format. Its own rounds, results format and review bookkeeping go.
- `agents/builder.md` keeps only its inputs and return format; its rules move into the template's Build step.
- `agents/router.md:46-47`: acceptance becomes "the worker reports `job done` succeeded; queue the merger". The router stops counting rounds; the worker returns `done`, `blocked: stuck`, `blocked: cap` or a question.

**Why BUILDER = yourself in a worker:** a worker already holds the code in context across rounds; spawning a fresh builder per round would add an agent per round per ticket for no independence gain, because test and review are already separate agents.

**Assumptions:** none on the harness. Preloading a skill into a subagent through frontmatter was considered and rejected below because I did not test it and `review-loop` sets `disable-model-invocation: true` (`SKILL.md:5`).

**Seen live, relevant here:** `/super-agents:write-eval` and `/super-agents:review-loop` both ran from a headless `claude -p` prompt, the second despite `disable-model-invocation: true`, and the single-feature flow completed in one round without a person (`evidence/live/run4-write-eval`, `run5-review-loop`). Only that one-round happy path was exercised: no fix round, no Stuck, no cap, no question to the user.

**Changed after testing:** the template's steps 3 and 4 say "start it in the foreground", for the reason given in (b).

**Files that change:** new `templates/loop.md`; `skills/review-loop/SKILL.md`, `agents/worker.md`, `agents/builder.md`, `agents/router.md`, `tests/run.sh` (static guards).

**Migration:** prompts only. A loop in flight continues under the new text because state lives in sa-core after (b).

**Rejected alternatives**
- *Worker spawns a builder subagent every round.* More agents and re-reading for no added independence.
- *Preload the skill into the worker via frontmatter.* Unverified harness behaviour; the template command is harness-neutral, in line with README.md:43.
- *Keep three texts and add a consistency test.* A test can compare numbers, not procedures.

---

### (f) Team mode: cut it

**Recommendation: remove team mode in v0.6.0.**

Evidence:
- It has never been exercised live (README.md:41) and depends on an experimental, interactive-only, non-resumable harness feature (README.md:109).
- It is the source of most special cases in the pipeline: ungated teammates (README.md:104); the merge and checker hold while a team builds (`agents/router.md:48`, `agents/merger.md:14`); "undo" that undoes nothing (`merger.md:17`); commit scope taken from an LLM-written `contract.md` (`merger.md:18`); the unnamed-agent rule (`router.md:42`); a second heartbeat file shape (`scripts/job-status.sh:6-7`, `core/src/scan.rs:188-191`); the session environment flag (`scripts/superagent.sh:22`).
- It conflicts with evidence binding: several agents editing one tree means the tree id moves under the tester.

What replaces it: `write-tickets` already has the mechanism. A ticket that "spans several independent areas" (`skills/write-tickets/SKILL.md:27`) becomes one small contract ticket (the shared names, written out in its `FR-` lines per `:17`) plus one solo ticket per area that `waits for` it. The areas then run in parallel in separate worktrees, gated and merged like every other ticket.

Why not a shared worktree per team: it still needs experimental teams and the ownership contract, still has concurrent edits under the tester, still cannot be covered by `tests/run.sh`, and adds a worktree that no single agent owns.

**Files that change:** delete `agents/teammate.md`; `agents/router.md` (`:15`, `:43`, `:48`), `agents/merger.md` (`:14`, `:16-18`), `skills/write-tickets/SKILL.md:27`, `scripts/superagent.sh:19-22`, `scripts/job-status.sh` (`--name`), `core/src/scan.rs:188-191`, `core/src/board.rs:189-191`, `README.md`.

**Migration:** the `Mode` column stays in `BOARD.md` so old boards parse. From v0.6.0 `board check` fails a `team` row with "team mode was removed: split the ticket or set it to solo", and the router refuses to dispatch it. Finish in-flight team tickets on v0.5.x before upgrading.

---

### (g) Runtime state, locking, recovery

**Current behaviour**
- Workers write `building` into tracked files in the main checkout (`agents/worker.md:15`, resolved by `core/src/main.rs:99-104`), although `worker.md:32` says never to touch it. The dirty tree forces exceptions in the merger (`merger.md:14`, `:18`).
- `BOARD.md` is rewritten in place under a lock that readers do not take (`core/src/board.rs:296-314`); `RD.md` is written with no lock (`board.rs:270`).
- One `state.md` per checkout, created by overwrite (`skills/review-loop/SKILL.md:21`), so a second loop replaces the first.
- Heartbeats are one file per worktree; the scan groups every worktree's file by ticket (`core/src/scan.rs:48-61`), so a dead worktree keeps reporting.
- "Start a fresh worker that continues in the existing worktree" (`agents/router.md:57`) contradicts the worker's isolation (`worker.md:7`, `:11`, `:13`).
- Nothing handles a leftover `MERGE_HEAD`.
- No notion of a flaky eval.
- The watchdog's change detection (`scripts/watchdog-loop.sh:8`) compares text that contains minute counts (`scan.rs:124`, `:146`).

**Location**

| What | Where | Tracked |
|---|---|---|
| Requirements, evals, fingerprint, mockup | `specs/.../{RD.md,evals.md,.evals.sha256,mockup.html}` | tickets: yes; single features: ignored |
| Approval status (`draft`, `ready`) and final `done` | `**Status:**` in `RD.md`, row in `BOARD.md` | yes |
| Runtime status (`building`), owner, worktree, branch, phase, heartbeat, round, counters, verified tree | `<main checkout>/.super-agents/state.json` | no (ignored; tracked-file rule applies) |
| Transition log | `<main checkout>/.super-agents/state.log` | no |

Tracked files therefore change at exactly two moments: approval (committed by `commit-tickets`) and `done` (committed by the merger). The tree is never dirty with status bookkeeping, so `':!specs/tickets'` (`merger.md:14`) and the "other tickets' status edits" caveat (`merger.md:18`) go away, and `drop-specs.sh:16-21` keeps working unchanged.

```json
{ "v": 1, "items": {
    "specs/tickets/003-profile": {
      "status": "building", "approved": "<sha256>", "base": "<sha>",
      "owner": { "kind": "worker", "session": "…" },
      "worktree": "/abs/.claude/worktrees/x", "branch": "worktree-x",
      "phase": "testing", "note": "", "started": "…", "updated": "…",
      "round": 2, "awaiting_user": false, "blocks": 1,
      "verified": { "tree": "…", "at": "…" } } } }
```

One record per item removes the per-worktree heartbeat files (`.job/status*.json`) and lets several single-feature loops coexist.

**Locking and atomic writes**
- One lock file, `.super-agents/state.lock`, taken with `File::lock` (already used at `board.rs:298`) for every read-modify-write.
- Every write goes to a temp file in the same directory, is flushed, then renamed over the target. This applies to `state.json`, `BOARD.md` and `RD.md`. Readers that take no lock (the router's Read tool, the scan) see the old or the new file, never a mix.
- On Windows a rename onto an open file can fail; retry three times, 50 ms apart, then exit 1.

**Recovery paths**

| Case | Design |
|---|---|
| Dead worktree heartbeat | There is one record per ticket. `job start NNN` from a new worktree replaces `worktree` and `branch` and logs the takeover. The scan reports `worktree gone` when the recorded path no longer exists. |
| Restarting a stuck worker | Restart means a **fresh worker in a fresh worktree**. The router passes `resume from <branch>` (it reads the branch from `state.json`); the worker's first step is `git merge --ff-only <branch>`. Uncommitted work in the dead worktree is lost by design; the loop's per-round checkpoint commit (`SKILL.md:53`) bounds that to one round. `router.md:57` is rewritten accordingly. |
| Leftover `MERGE_HEAD` | Merger step 0 aborts it and reports. `board set … done` refuses while `MERGE_HEAD` exists. Safe now because the tree no longer carries status edits. |
| Flaky eval | Definition: two runs on the same tree id disagree. The tester re-runs a failing eval once; if the second run passes it records `flaky` with `runs 1/2`. `flaky` is not `pass` for the gate. The loop does not send it to the builder and does not count it toward Stuck: it runs `loop await` and asks the user to fix the eval (re-approve) or the non-determinism. High-risk features run every eval twice on the final tree and need `2/2`. |
| Watchdog repeats | A problem line becomes `PROBLEM <id> <kind> :: <details>`. `watchdog-loop.sh` compares only the part before ` :: `, and re-emits a persisting problem every `renotify_min` (default 30). This makes `agents/watchdog.md:13` true. |
| Worker hits `maxTurns` or dies | Its record stays `building` with an old heartbeat; the scan reports it; the restart path above applies. |

**Assumptions, now tested**
- *A worker may run `git merge --ff-only <other branch>` inside its own worktree.* **Verified** with Bash allowed in the default permission mode (`evidence/live/run1-main-probe`, step 9) and under `--permission-mode auto`, the mode `superagent` uses (`evidence/live/run8-auto-mode-worktree`, step 3). In the same run `git add -A`, `git commit` and a `git status --short && git log` chain were allowed, while `cd .. && git status` and `git -C ../../.. …` were refused with "a worktree-isolated agent's git operations must target its own worktree". So `worker.md:11` is right about the mechanism and stricter than needed about `&&`.
- *A worktree is created from the local HEAD of the integration branch.* **Refuted when a remote exists**, verified without one, and fixable with `worktree.baseRef: "head"`; details under (b).
- *Writes outside the worktree are refused.* **Verified for the Write tool** ("Edit the worktree copy of this file instead of the shared-checkout path") and **refuted for Bash**: `echo … > ../../../file` from the worktree created the file in the main checkout (`run8`, steps 11 and 12). This matches `README.md:112`.
- *The router can Read `.super-agents/state.json`.* Not tested. A main thread with `tools: Read, Agent(...)` did have Read and no Bash (`evidence/live/run3-router-allowlist`, step 4).

**Seen live, relevant here**
- A finished agent's worktree is kept when it holds changes or commits and **removed when it is clean** (`run7`: the stub worker's worktree, with its `.job/` folder, was gone after the run; `run1`, `run8`: kept). Heartbeats kept in the worktree disappear with it, which is one more reason for the single record in the main checkout.

**Changed after testing**
- The restart protocol keeps its fast-forward step; the "blocked: cannot resume" fallback is no longer expected to trigger.
- Worktree base: the launcher setting and the `job start` ancestry check moved from "fallback" to "required", and into v0.4.1.

**Files that change:** new `core/src/state.rs`; `core/src/board.rs`, `core/src/scan.rs`, `scripts/job-status.sh`, `scripts/watchdog-loop.sh`, `agents/worker.md`, `agents/merger.md`, `agents/router.md`, `agents/watchdog.md`, `agents/tester.md`, `scripts/init-project.sh`.

**Migration:** `board migrate` (section b). Old `.job/` directories are ignored after the upgrade and removed with their worktrees. A tracked `building` left in `BOARD.md` or `RD.md` is rewritten to `ready` by `board migrate`, and `commit-tickets` commits that.

**Rejected alternatives**
- *State outside the repository (`$XDG_STATE_HOME`).* Immune to repo content and to the Edit tool, but the router's read access and Windows paths are unverified; see open decision 4.
- *Lock `BOARD.md` itself for readers too.* The router reads with the Read tool and cannot take a lock.
- *A state daemon.* A file, a lock and a rename are enough at this scale.
- *Auto-accept flaky evals by N-of-M.* Turns "proven" into "probably".

---

### (h) Fail-closed rules and the launcher

**Current behaviour**
- sa-core missing: every hook exits 0 (`eval-gate.sh:8`, `worker-gate.sh:7`, `block-code-reads.sh:6`, `session-start.sh:4`); README.md:10 documents it.
- Malformed hook JSON: `hookio get` exits 1 (`core/src/main.rs:107-114`) but the scripts read only stdout, so every gate sees empty values and passes (probed; admitted at `core/src/hookio.rs:156-158`).
- Untrusted dir: `eval-gate.sh:15` validates and then exits silently; `worker-gate.sh:12` does not validate.
- Launcher: `scripts/sa-native.sh:17` runs `$SUPER_AGENTS_CORE` unchecked; `:18` prefers any local build; `:23` verifies the cached binary only at download time; `--version` is called but never compared (`eval-gate.sh:8`).
- All of the above reproduced offline (`evidence/A-repro.out`): A6, malformed JSON gives exit 0 with no block or deny from all three hooks; A8, with no local build, an empty cache and an unreachable download every hook exits 0 with a notice, and a second call within ten minutes does not retry; A8b, a download with the wrong checksum is refused (the good part); A8c, a tampered file already in the cache is executed without a check.

**Rules**

| Condition | Transition commands | Stop / SubagentStop (nudges) | PreToolUse (the only control on its path) |
|---|---|---|---|
| sa-core unavailable (launcher exit 3) | fail: nothing can become `ready`, `building` or `done` | allow, and say so in a `systemMessage` every time | deny for the first-time-user agent and for Edit/Write on the protected basenames, using a literal JSON reply that needs no helper; allow everything else |
| Hook JSON does not parse | n/a | allow with `systemMessage` "hook input unreadable; gate not evaluated" | deny when the raw input matches the cheap pre-filter (`first-time-user`, or a protected basename with an Edit/Write tool name); allow otherwise |
| `dir` fails the grammar, leaves `specs/`, or is not registered | refuse, exit 1, name the reason | no loop is found; message, no block | rule does not apply |
| Runtime file tracked or a symlink | refuse, exit 1 | ignore the file; fixed message | treat status as unknown: rules 1-3 in (d) deny |
| Fingerprint missing | `verify` fails (as `check-evals.sh:56-58` today) | n/a | n/a |

The important change is structural: with transitions in sa-core, a missing or broken helper can no longer lead to `done`, so the Stop hooks are free to stay out of the way of unrelated sessions.

All hook logic moves behind one entry point so that no shell code parses hook input:

```
sa-core hook session-start | stop | subagent-stop | pre-tool      # reads the hook JSON on stdin, prints the reply
```

**Launcher rules (`scripts/sa-native.sh`)**
1. **Pinned binary.** The release asset for the plugin version, sha256 from `dist/checksums/v<version>.txt` (unchanged, `:24-43`).
2. **Re-verify on every run.** Hash the cached binary before `exec`; on mismatch delete it, download once more, otherwise exit 3. The PreToolUse script reaches the launcher only after its pre-filter (`block-code-reads.sh:5`), so the per-call cost lands on Stop, SessionStart and real commands.
3. **Version check, one exec.** The launcher passes `--expect-version <plugin version>`; sa-core exits 3 if it differs. A binary too old to know the flag prints usage and exits 1, which the launcher treats as a mismatch.
4. **Local build** (`core/target/release/sa-core`): used only when rule 3 passes; otherwise fall through to the pinned binary with one stderr line.
5. **`SUPER_AGENTS_CORE`**: still honoured, also subject to rule 3.
6. **Exit code 3** keeps meaning "helper unavailable" (`:5-6`); every caller maps it through the table above instead of treating it as "allow".

**Files that change:** `scripts/sa-native.sh`, `core/src/main.rs`, new `core/src/hook.rs`, all four hook scripts, `README.md:10`, `core/tests/launcher.rs`.

**Migration:** a developer with a stale local build gets the pinned binary plus a one-line notice. Nothing else changes for users.

**Rejected alternatives**
- *Block every Stop when sa-core is missing.* Wedges every session in every repository, including ones with no loop.
- *Verify the cached binary once per session with a stamp file.* The stamp is as writable as the binary.
- *Go back to Python or jq to avoid the binary.* Windows support was the stated reason for the move (`docs/superpowers/plans/2026-11-07-sa-core.md:39-40`; `:51` records the goal as "a plugin with no interpreter dependency"), and the pinned-binary pipeline is sound.

---

## 3. Roadmap

### v0.4.1: security and hardening (effort S overall; no format changes)

Order (items marked NEW were added after testing):
1. **(S) Arithmetic and grammar fixes, tracked-file rule** (a) in `eval-gate.sh`, `worker-gate.sh`, `session-start.sh`, `job-status.sh`.
2. **(S, NEW) Worktree base.** `scripts/superagent.sh` passes `--settings '{"worktree":{"baseRef":"head"}}'`; the worker's first step fails loudly when its ticket folder is missing or the integration HEAD is not an ancestor of its HEAD. Without this, in any repository that has a remote, workers start from the remote's default branch and do not see the tickets.
3. **(S, NEW) The Stop gate ignores stops while a subagent runs** (`background_tasks` in the payload), and the review-loop text asks for foreground subagents. Without this the gate spends its three blocks on waits and is off for the rest of the round.
4. **(S) Worker gate resolves the ticket folder from the ticket number**, not from `dir`.
5. **(S) Gates report a failed `hookio get`** instead of treating it as empty.
6. **(S) Launcher: re-verify the cache, version check, local-build rule** (h).
7. **(S) Tool allowlists** for reviewer and builder (d). No hook work yet.
8. **(S) Merger step 0 (`MERGE_HEAD`)** and **watchdog dedupe keys** (g).
9. **(S) `init-project.sh`: stop ignoring the project's own files under `specs/`.** Replace `specs/*` and `!specs/tickets/` (`:31`; probed: a new `specs/openapi.yaml` is ignored) with patterns for the plugin's files (`specs/*/RD.md`, `evals.md`, `.evals.sha256`, `results.md`, `mockup.html`, `evidence/`) and negations for `specs/tickets/`. Setup removes the two legacy lines it added.
10. **(S) README corrections** for the claims in review section 4, plus `README.md:51` (worktree base) and `README.md:103` (what the Stop gate does while subagents run).

Tests:
- The cases in `evidence/A-repro.sh` are written to be lifted into `tests/run.sh` with the verdicts inverted: A1, A1b, A2, A5, A5b, A6, A8c, A9a, A9b, A9c.
- `tests/run.sh`, eval-gate section (`:145`): `gate-arith-injection` (hostile `gate_blocks`; marker file must not exist; gate still blocks), `gate-tracked-state-ignored`, `gate-symlink-state-ignored`, `gate-bad-json-says-so`, and NEW `gate-allows-while-subagent-runs` (a payload with one running entry in `background_tasks` is allowed and does not count a block) with `gate-blocks-when-no-task-runs`.
- `tests/run.sh`, superagent section (`:308`): NEW `launch-sets-worktree-base` (the fake `claude` records its arguments; they must include the `worktree.baseRef` setting).
- `tests/run.sh`, worker-gate section (`:178`): `worker-gate-arith-injection`, `worker-gate-foreign-dir` (the review's probe), `job-name-grammar`.
- `tests/run.sh`, hooks section (`:408`): `session-hostile-dir` (context contains none of the hostile text).
- `tests/run.sh`, sa-native section (`:499`): `native-cache-tampered`, `native-stale-local-build`, `native-version-mismatch`; extend `core/tests/launcher.rs`.
- `tests/run.sh`, consistency section (`:467`): every agent file has a `tools:` line and none has `disallowedTools`.
- `tests/run.sh`, next to the H1 fixture (`:452`): `merge-head-recovery`.
- `core/tests/board_scan.rs` and `tests/run.sh:208-257`: problem lines in `kind :: details` form; a persisting problem is silent on the second round.
- `tests/run.sh`, init section (`:259`): `init-specs-own-files-tracked`, `init-legacy-ignore-removed`.

Breaking changes: the reviewer and builder lose MCP connectors, web tools and the Agent tool; watchdog problem text changes (anything parsing it by eye only).

Rollout risk: low. The harness facts items 2-4 rely on (worktree base setting, `background_tasks` in the Stop payload, SubagentStop `cwd`) were all observed on Claude Code 2.1.322; they are undocumented here and could change with the CLI, so each gets a test with a recorded payload.

### v0.5.0: transitions and evidence binding (effort L)

Order (each step is shippable behind the previous):
1. **(M) `state.json`, lock, atomic writes, log; `board migrate`** (g). `building` stops being written to tracked files.
2. **(M) Port `check-evals.sh` to `sa-core verify`**; the script becomes a wrapper with identical flags and output.
3. **(M) Edges with preconditions** on `board set`; `loop` and `job` commands (b).
4. **(M) `tree-id`, `result` (with `exec`), `verdict`, the results record with its rendered `results.md`, verify checks 2-5** (c).
5. **(M) `sa-core hook …` entry point**; Stop and SubagentStop semantics from (b); fail-closed table from (h).
6. **(S) PreToolUse rules 1-6** (d).
7. **(M) Prompts:** tester starts its own server and records through the CLI; review-loop and worker stop writing `results.md`; merger gains the merged-tree test and project tests; router acceptance simplified; flaky rule.
8. **(M) A scripted live smoke run**, because README.md:126 states the router, workers and merger have no automated test: a fixture project with two tickets, one whose E2 cannot pass. Run by hand before the release; pass criteria are mechanical (`state.json` statuses, `git log`, the unsatisfiable ticket is not `done`). The runner and logging hook used for this document (`evidence/run-claude.sh`, `evidence/hooks/probe-log.sh`, `evidence/C-setup.sh`) are a working starting point: they isolate the session from the user's own plugin and record every hook payload. One data point for cost: the one-round single-feature loop on Sonnet cost $0.41 and about 90 seconds.

Tests:
- New `core/tests/state.rs`: every (from, to) pair is allowed or refused per the table; `ready` never re-fingerprints after the first approval; `--reset` refuses changed evals.
- New `core/tests/state_concurrency.rs`: many processes flipping different tickets; the file is always valid JSON and no update is lost.
- New `core/tests/verify.rs`: the cases at `tests/run.sh:84-143`, which also keep running through the wrapper as the compatibility proof.
- New `core/tests/tree_id.rs`: stable across a commit; changes on an edit and on a new untracked file; ignores `specs/tickets` and git-ignored files.
- New `core/tests/results.rs`: `add` refuses a missing or empty evidence file, a path outside `evidence/`, and a tree that moved since `begin`; `end` refuses a missing eval.
- New `core/tests/hook.rs`: Stop blocks an unfinished loop three times then releases with status still `building`; a non-owner session is not blocked; malformed input per the (h) table; pre-tool rules 1-6 with their exceptions.
- `tests/run.sh`, eval-gate and worker-gate sections rewritten: `done-path-is-gated` (failing evals plus `loop finish` gives exit 1 and status `building`), `stale-tree-rejected`, `swapped-evidence-rejected`, `old-format-results-rejected`, `review-verdict-required`.
- `tests/run.sh`, consistency section: `worker.md` and `SKILL.md` contain no hand-written results table; `merger.md` names the tester step; no file mentions `findings-fixed`.
- New model-run case `evals/review-loop-cannot-self-certify/` (run by hand with Bash allowed, since the current cases run without it, README.md:126): a feature with one unsatisfiable eval; graders check the status is not `done` and the final message names the unmet eval.

Breaking changes: `results.md` v1 is rejected (rerun the tester); hooks stop reading `state.md` (`loop adopt` for one release); `findings-fixed` is gone; subagents can no longer approve; every merge runs the tester once more (cost); the tester no longer reuses a running server (slower rounds).

Rollout risk: medium to high. More logic in the gate path; the merged-tree run adds one tester per ticket. `tree-id` cost is no longer a concern at the sizes measured (under 100 ms at 60,000 files). Mitigation: ship steps 1-2 first as a release candidate, since they are behaviour-preserving, and run the live smoke before tagging.

### v0.6.0: structural (effort M to L)

Order:
1. **(M) Loop unification** (e).
2. **(M) Cut team mode** (f).
3. **(S) Restart protocol and worktree cleanup** (g); remove `.job/` handling and `loop adopt`.
4. **(M) First-time-user: allowlist instead of the shell parser.** Browser apps: the agent loses Bash. Command-line apps: Bash is allowed only for the launcher path the skill registered (`super-agents ftu allow <path>`) and `curl` to localhost with a short flag allowlist, with no `;`, `&`, `$`, backtick or redirection. Replaces most of `scripts/block-code-reads.sh:20-140`.
5. **(S) One final sweep before `drop specs`:** the tester runs every ticket's evals once on the finished integration branch (pending open decision 3).
6. **(S) Remove byte-compatibility with the deleted Python:** the custom serialiser (`core/src/hookio.rs:75-154`) and the tuple text (`core/src/board.rs:27-28`).

Tests:
- `tests/run.sh`, consistency section: the skill and the worker both reference `super-agents template loop.md`, and neither states its own round limit; no agent or skill references `super-agents:teammate`.
- `core/tests/board_check.rs`: a `team` row fails with the removal message.
- `tests/run.sh`, hooks section (`:346-403`): the existing allowed cases that should stay allowed, plus the review's probes denied (`while read … < main.py`, `mapfile < main.py`, `curl -d @main.py`, `c""at main.py`).
- `core/tests/hookio.rs`: replies parse and carry the same keys at the same paths (not the same bytes).
- The v0.5.0 live smoke, extended with a restart of a killed worker.

Breaking changes: team tickets must be split; worker round limit changes from 3 to 5; the first-time-user agent can no longer pipe output through filters; `.job/` is gone.

Rollout risk: medium. Prompt-level changes can only be proven by the live smoke.

### Do not do

- **Do not try to make agents forgery-proof under one user account** (signed results, hidden keys, a chroot for the first-time-user). Bash under the same account defeats each; README.md:113 already gives the real answer.
- **Do not grow regex rules over Bash commands.** Four fixed strings are in the design; the 140-line parser and its probed bypasses are the warning.
- **Do not block Stop for everyone when sa-core is missing.** Transitions already fail closed.
- **Do not remove the 3-block cap.** Make release different from `done` instead.
- **Do not rewrite `init-project.sh`, `commit-tickets.sh`, `drop-specs.sh` or `superagent.sh` in Rust.** They are off the gate path and well covered (`tests/run.sh:259-336`).
- **Do not re-run every earlier ticket's evals after every merge.** Quadratic cost; one final sweep finds the same regressions once.
- **Do not cache passes for "unaffected" evals.** Needs a dependency model whose mistakes are silent false passes.
- **Do not put a model in the gate** to judge evidence content. The gate must be deterministic.
- **Do not keep team mode behind a flag.** Unexercised paths rot, and it has never been exercised.
- **Do not make the watchdog smarter.** Fix the dedupe; liveness comes from the single record per ticket.
- **Do not convert old `results.md` files.** That would create proof that was never produced.

---

## 4. Open decisions for the user

1. **Team mode: cut, or keep with a shared worktree?**
   Recommendation: cut (f). If kept: v0.6.0 grows by roughly an M-L item, the experimental-teams dependency and the ownership contract stay, the tester may only run after every teammate has stopped editing, and the mode remains outside automated tests.

2. **How strong should approval be?**
   Recommendation: keep `/super-agents:mark-ready` in the session and deny `ready` for subagents by hook (nudge-strength; that a hook can single out subagents is now verified). The alternative is a terminal-only `super-agents approve` that refuses without a TTY: no agent can approve at all, but `write-eval` step 7 (`skills/write-eval/SKILL.md:22`) can no longer set `ready` itself, and other harnesses lose in-session approval.

3. **How much regression testing on merge?**
   Recommendation: the merged ticket's evals plus the project's tests on every merge, and one final sweep of all tickets before `drop specs`. Cheaper: no sweep (cross-ticket regressions are left to the checker's browser walk, which covers nothing for non-UI tickets, `agents/checker.md:11-12`). Stricter: all earlier tickets on every merge (quadratic cost).

4. **Where does runtime state live?**
   Recommendation: `<main checkout>/.super-agents/state.json` with the tracked-file rule; the router can read it and worktrees resolve it through `core/src/gitroot.rs`. The alternative, a per-user state directory outside the repository, is immune to repo content and to the Edit tool, but the router's read access and Windows path handling are unverified and it needs a repository-to-file mapping.

5. **Flaky evals and high-risk double runs.**
   Recommendation: `flaky` is never a pass and goes to the user; high-risk features need `2/2` on the final tree. Choosing N-of-M auto-acceptance removes the pause but weakens "proven"; dropping the double run halves the final test cost for high-risk work and leaves single lucky passes undetected.

---

## Appendix: test evidence

All paths are under `evidence/`, next to this file. Plugin under test: copies of commit `c3810c1` with sa-core built from source offline. The real repository, `~/.claude` settings and the user's installed plugin were not touched; each run's debug log shows the copy as the only `super-agents` plugin loaded (`live/run1-main-probe/isolation-check.txt`).

### A. Review findings, reproduced offline (`A-repro.sh`, `A-repro.out`)

| # | Finding | Result |
|---|---|---|
| A1, A1b | Command execution through `gate_blocks` in `state.md`, also from a fresh clone that tracks the file | Reproduced. My first A1b run said "not reproduced": the test reused a repository whose `state.md` the hook had already rewritten. Fixed the test, then reproduced. |
| A2 | The same through `.job/gate_blocks` in the worker gate | Reproduced (the review had inferred it, not run it) |
| A3 | Failing evals: blocked with `active: true`, silent pass with `active: false` or `awaiting_user: true` | Reproduced |
| A4 | `board set ready` re-fingerprints edited evals; the gate then passes | Reproduced |
| A5, A5b | Worker gate trusts `dir` from `status.json`; a worker-written counter releases it | Reproduced |
| A6 | Malformed hook JSON: exit 0, no block, no deny, from all three hooks | Reproduced |
| A7 | First-time-user denylist: `while read … < main.py`, `mapfile`, `read`, `curl -d @file`, `curl -T file`, `c""at` | Reproduced: 6 of 6 allowed; `cat main.py` denied as the control |
| A8, A8b, A8c | Launcher with the pinned binary absent | Every hook off with a notice; wrong-checksum download refused; tampered cache entry executed |
| A9a-c | Session-start text injection; watchdog text changes each round; setup ignores the project's own `specs/` files | Reproduced |

### B. Harness assumptions (8 live runs; `live/costs.txt`)

| # | Assumption | Result | Evidence |
|---|---|---|---|
| 1 | SubagentStop `cwd` is the worker's worktree | Verified, also with the real `worker-gate.sh` | `live/run1-main-probe`, `live/run7-worker-gate` |
| 2 | `agent_type` empty in the main session, `<plugin>:<agent>` in a subagent | Verified for an ordinary session; **refuted under `--agent`** (main thread carries the agent's type). `agent_id` is the reliable marker | `live/run1`, `live/run3`, `live/agent_id-check.txt` |
| 3 | Edit and Write carry `tool_input.file_path` | Verified. NotebookEdit: `notebook_path` | `live/run1` |
| 4 | Worktrees branch from the local HEAD | **Refuted with a remote** (starts at `origin/main`); verified with no remote; verified with `worktree.baseRef: "head"` | `live/run1`, `live/run3`, `live/run2`, `B4-baseRef-binary-strings.txt` |
| 5 | `session_id` stable across resume | Verified for `--resume` | `live/run2` |
| 6 | A merger-type subagent can start the tester | Verified: nesting works, to depth 3 | `live/run1`, `live/run3` |
| 7 | A worker can fast-forward to a previous branch in its worktree | Verified in default and auto permission modes | `live/run1`, `live/run8` |
| 8 | The router's `Agent(...)` list binds descendants | Verified. But a subagent's own `Agent(...)` list is **not** enforced | `live/run3`, `live/run1` |
| 9 | A PreToolUse hook can deny one `agent_type` from the payload | Verified | `live/run1`, `hooks/probe-deny.sh` |
| 10 | Tree-id cost | 47-89 ms on 60,000 files with a copied index; 636 ms without | `B10-tree-id.out` |
| extra | Subagent `tools:` allowlist enforced; reviewer's `disallowedTools` leaves Bash, Agent and web tools | Verified | `live/run6-tool-lists` |

### C. Live single-feature flow (`live/run4-write-eval`, `live/run5-review-loop`, `live/C-artifacts`)

`write-eval` ran on Haiku ($0.02) and stopped at `draft`, as documented. I approved by running the two `mark-ready` commands in a shell. `review-loop` ran on Sonnet ($0.41), headless, and finished in one round: 7 of 7 evals, review clean, one commit on `feat/greet`.

| Question | What happened |
|---|---|
| Did the Stop hook fire? | Seven times. Three blocks in the first 12 seconds while the builder was starting, two "released after 3 blocks", one silent pass while the review was still pending, one silent exit after `active: false` |
| Did the tester run the evals? | Yes, all seven, in one Bash call, in a temporary copy of the tree. Evidence files hold output without the command |
| Did the reviewer stay read-only? | Yes in practice: two Bash commands, nothing written in the repository (two temp files under `/tmp`) |
| Did `active: false` end the loop? | Yes. The orchestrator set it with `sed`, after running `check-evals --passed` itself; the gate did not evaluate at the end |
| Who wrote `results.md`? | The orchestrator, with a shell heredoc, as `SKILL.md:42` tells it to. Not the tester |
| Anything the docs do not say | Subagents ran in the background; no Edit or Write call was made by anyone; `checkpoint:` in `state.md` was never updated after the commit |

Not exercised: a fix round, Stuck, the round cap, a question to the user, a failing run.

### What contradicts my earlier review or design

1. **Worktree base.** The review listed it as unverified and the design treated "local HEAD" as the expected case. With a remote it is false, and it affects every ticket run in a cloned repository. Now a v0.4.1 item.
2. **The Stop gate's real behaviour.** The review said the gate "only catches a turn that ends mid-protocol". Live, it did not do that usefully either: it blocked waits and then switched itself off. Revision 1's Stop rule would have done the same; it now checks `background_tasks` first.
3. **Scoped `Agent(...)` lists and Edit/Write deny rules.** Revision 1 proposed both as controls. The first is not enforced on subagents; the second matched nothing in the live run. Both are changed in (d).

### Side effects of the testing

- **`~/Projects/Hermes Agent Auto`** was used read-only for the tree-id timing. No object, index, ref or file content changed, but git refreshed the modification time of 11 existing loose objects and one pack file in its `.git/objects` (`B10-side-effect.txt`). I did not revert it, to avoid a second write.
- **`~/.claude/projects/`** gained four session-transcript folders, one per scratch repository, written by the CLI itself. No settings file was edited.

### Still not verified

- The multi-ticket router flow with the real router, worker, merger and checker (not attempted: the run cap was used up by B and C).
- The real worker in a repository with a remote (the base-ref result comes from a probe agent with the same isolation).
- Team mode; `session_id` across compaction or `--continue`; MCP connector inheritance by the reviewer; how the interactive UI shows `systemMessage`.
- Tree-id cost on a repository larger than 60,000 files.
- `core/src/isotime.rs` and the bodies of `core/tests/` were not read; the plan document was skimmed.
- Everything was observed on one CLI version (2.1.322) on Linux.
