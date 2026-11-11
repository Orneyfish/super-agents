# super-agents design review (branch release/v0.4.0, commit c3810c1)

Round-1 review by a read-only Fable 5.2 subagent. Written to the repo on 2026-11-11 from the agent's hand-back report.
Companion: [2026-11-11-design-changes.md](2026-11-11-design-changes.md), which builds on this review and was revised after
live testing. Three points here were corrected by that testing (worktree base branch, the Stop gate being weaker than
described, and two proposed controls that do not work); see its appendix.

**What was run:** `CARGO_NET_OFFLINE=true bash tests/run.sh` -> `500 passed, 0 failed`; `CARGO_NET_OFFLINE=true cargo test --locked` in `core/` -> 43 passed, 0 failed. Both wrote only to git-ignored `core/target` and temp dirs. Small probes were also run against the real scripts in a scratch area; findings marked "probed" come from those.

All paths below are relative to the repository root.

## 1. Architecture

- **Single feature:** `write-eval` writes `specs/<name>/{RD.md,evals.md}` as draft. The user approves, and `board set ready` writes `.evals.sha256`. `review-loop` then orchestrates builder -> tester -> reviewer for up to 5 rounds in the user's checkout.
- **Many features:** `write-tickets` writes `specs/tickets/NNN-*/` and `BOARD.md`; `mark-ready` approves; `superagent` starts the router, which starts one worker per ticket in a worktree. Each worker spawns its own tester and reviewer. The router then runs merger -> checker -> (reproducer) -> `drop-specs`.
- **State owners:**
  - `BOARD.md` and the RD `**Status:**` line: sa-core `board set`, always in the main checkout.
  - `.super-agents/state.md`: hand-edited by the review-loop orchestrator, plus the Stop hook.
  - `results.md`: written by the orchestrator or the worker, not the tester.
  - `.job/status*.json`: worker heartbeats.
  - `evals.md` and `RD.md`: the user, by convention.
- **Hook-enforced:** a turn cannot end mid-loop with unmet evals (Stop); a worker cannot finish with unmet evals (SubagentStop); the first-time-user denylist (PreToolUse). The router's tool allowlist is also real.
- **Prompt-only:** everything else, including "never edit evals", the review verdict, read-only reviewer/checker, the router's acceptance check, merge rules, and never touching the main checkout.

## 2. What the design gets right

- The router has no shell or write tools (`agents/router.md:4`), and it reads approved files from the main checkout, not the worker's copy (`router.md:46`).
- The fingerprint is anchored to the main checkout for worktrees (`scripts/check-evals.sh:44-48`). The merger pins `$SHA` and refuses branches that changed approved files (`agents/merger.md:15`).
- The merger uses `merge --no-commit`, then lint/build, then commit, which avoids the revert-of-a-merge trap (`merger.md:16-17`, tested at `tests/run.sh:452-459`).
- The sa-core supply chain is sound: per-version sha256 committed in the repo, a mismatch is never executed (`scripts/sa-native.sh:40-43`), the release workflow checks the draft against committed checksums with the write token only in `publish` (`release.yml:33-50`), and actions are SHA-pinned.
- `drop-specs` fails closed on the committed board (`scripts/drop-specs.sh:16-21`).
- Requirement-to-eval coverage is checked mechanically (`check-evals.sh:19-22`).

## 3. Design problems, by severity

**P1. Code execution from repo content in the Stop hook (probed).**
- Evidence: `scripts/eval-gate.sh:24-28` does `n=$(get gate_blocks)` and then `$((n+1))` on a raw string from `.super-agents/state.md`. `worker-gate.sh:15-17` has the same pattern on `.job/gate_blocks`.
- Scenario: `.gitignore` does not stop a hostile repo from tracking `state.md`. With `active: true`, a valid `dir:` and `gate_blocks: x[$(cmd)]`, the first turn-end in that clone runs `cmd` with no permission prompt. The probe created the marker file.
- Related: `session-start.sh:15` injects unvalidated `dir:`/`round:` text into every session's context.
- Fix: accept only `^[0-9]+$`; ignore a git-tracked `state.md`; reuse the line-15 `dir` validation in `session-start.sh`.

**P2. The "done" transition itself is ungated.**
- Evidence: `skills/review-loop/SKILL.md:63` makes "Set `active: false`" the first step of Finish, and `eval-gate.sh:13` exits when `active` is not true.
- Scenario: on the normal Done path the hook never evaluates (probed: failing evals with `active: false` gives rc 0, no block). The gate only catches a turn that ends mid-protocol.
- Other self-service exits: `awaiting_user` (the block message advertises it, `eval-gate.sh:32`), a `gate_blocks` counter the gated agent resets itself (`SKILL.md:40`), and `.job/gate_blocks`, which the worker can write (probed).
- `board set ... done|ready` validates nothing (`core/src/board.rs:243-246`). Any agent can re-fingerprint edited evals with `board set <dir> ready` (`board.rs:274-278`).
- Fix: `board set <x> done` runs `check-evals --passed` and refuses; the hook, not the agent, clears `active`; `ready` refuses when the current status is `building` or `done`.

**P3. Evidence is not bound to the code that lands; builders certify themselves.**
- The gate checks only a `pass` cell and a non-empty file (`check-evals.sh:59-66`). There is no commit, time or session binding, and the `**Review:**` line is never checked.
- `results.md` is written by the gated party (`agents/worker.md:21`, `SKILL.md:42`).
- After review fixes the worker re-tests only "the failing evals and their neighbours" (`worker.md:20`), so other pass rows predate the final code.
- The router accepts `findings-fixed` (`router.md:46`), a term nothing defines and which the worker declares itself (`worker.md:25`).
- The tester uses whatever answers on the port (`agents/tester.md:13`), which can be a stale server.
- The merged result is never tested: the merger runs lint and build only, even after resolving conflicts by hand (`merger.md:16-17`). The router is told never to start the tester (`router.md:21`).
- Fix branches merge on the reproducer's own word (`router.md:49`).
- The only independent check, the checker, is browser-only on port 3000 (`agents/checker.md:11-12`), so non-UI tickets get none.
- Fix: the tester writes `results.md` with the HEAD sha it tested and the gate compares it; the router runs the tester on the merged tree before the merge commit.

**P4. Gates fail open and trust agent-written inputs.**
- sa-core missing means every gate is off (`eval-gate.sh:8`, `worker-gate.sh:7`, `block-code-reads.sh:6`).
- Malformed hook JSON gives empty values and exit 0 (probed; admitted at `core/src/hookio.rs:156-158`).
- The worker gate takes the ticket `dir` from the worker's own `status.json` (`worker-gate.sh:12`). Probed: a dir outside the repo with a self-written fingerprint passes.
- Fix: derive `dir` from the board plus the ticket number; treat a failed `hookio get` as an error, not as empty.

**P5. Team mode undermines isolation.**
- Teammates build uncommitted in the main checkout and are ungated (`README.md:104`).
- One building team ticket holds every solo merge and the checker (`router.md:48`, `merger.md:14`).
- "Undo" for a team ticket is "commit nothing" (`merger.md:17`), so a failed team build leaves a dirty tree that blocks the queue until a human steps in.
- The commit scope comes from an LLM-written `contract.md` (`merger.md:18`).
- README admits it was never exercised live (`README.md:41`).
- Fix: one shared worktree per team ticket, then the normal merge path; or cut the mode.

**P6. Runtime status lives in tracked files, written by workers into the main checkout.**
- `worker.md:15` runs `board set`, which targets the main checkout (`core/src/main.rs:99-104`). `worker.md:32` says "never touch the main checkout".
- This is the source of the dirty-tree special cases (`merger.md:14`, `:18`). The board is also rewritten in place, and readers take no lock (`board.rs:296-314`).
- Fix: keep `building`/`done` in untracked `.super-agents/`, and only approval in git.

**P7. Recovery paths contradict each other or are missing.**
- "Start a fresh worker that continues in the existing worktree" (`router.md:57`), but workers have `isolation: worktree` and are told the harness refuses work outside their own (`worker.md:7,11,13`).
- A dead worktree's stale heartbeat keeps reporting, because scan groups by ticket across all worktrees (`core/src/scan.rs:48-61`).
- The watchdog's "only when changed" dedupe (`scripts/watchdog-loop.sh:8`) is defeated by minute counts in the text (`scan.rs:124,146`), so a persistent problem wakes the LLM every interval.
- A merger killed mid-merge leaves `MERGE_HEAD`, and no step handles it.
- There is no notion of a flaky eval: one lucky pass is never rerun, and a flaky fail burns rounds.

**P8. Agents have more power than their roles need.**
- The reviewer is a denylist of three tools (`agents/reviewer.md:4`). The builder has no `tools` line. Both inherit Bash, Agent and every MCP connector in the user's session, under `--permission-mode auto` (`scripts/superagent.sh:21`).
- The worker's `Agent` is unrestricted (`worker.md:4`).
- The existing PreToolUse hook is not used to deny Edit/Write on `evals.md`, `RD.md` or `.evals.sha256` for builder/worker, which is the cheapest real enforcement available.

**P9. Complexity is in the wrong places, and there is drift.**
- The loop is specified three times with different rules: 5 rounds and `clean` required (`SKILL.md:55-57`), 3 rounds (`worker.md:20`), 3 rounds (`agents/teammate.md:15`).
- Checker and first-time-user overlap; reproducer and `fix-bug` overlap.
- The largest script is a 140-line bash shell parser (`block-code-reads.sh`) for a side feature. Probed: `while read l; do echo "$l"; done < main.py` and `curl -d @main.py ...` are allowed. An allowlist (launcher or curl-to-localhost only) would be shorter and fail closed.
- sa-core keeps byte compatibility with deleted Python: a custom JSON serializer (`hookio.rs:75-154`) and a Python-tuple message (`board.rs:27-28`).
- A stale local build silently shadows the pinned binary (`sa-native.sh:18`). The cached binary is never re-verified (`sa-native.sh:23`). `--version` is never compared to `plugin.json`.
- Setup ignores `specs/*` (`scripts/init-project.sh:31`). Probed: a new `specs/openapi.yaml` becomes git-ignored.

## 4. Claims the code does not back

- **"Proven in this session."** `session-start.sh:7`: "proven with output run in this session". `check-evals.sh:65` is `[ -s "$d/$ef" ]`, which accepts any old non-empty file.
- **Stop gate.** `README.md:103`: "blocks 'done' until every eval passes". `SKILL.md:63`: "Set `active: false`", after which `eval-gate.sh:13` exits.
- **Read-only.** `README.md:81` "read-only reviewer" and `checker.md:3` "read-only". `reviewer.md:4` disallows only Edit/Write/NotebookEdit, and `checker.md:4` includes Bash.
- **Tester.** `tester.md:3`: "Runs a ticket's evals exactly as written". `tester.md:13`: "if something answers on the given port, use it"; `worker.md:20` re-tests a subset.
- **Merger.** `README.md:76`: "merges without committing, runs lint + build, then commits or aborts". `merger.md:17`: "(a team ticket: commit nothing)".
- **Watchdog.** `agents/watchdog.md:13`: "only when the set of problems changed". `scan.rs:124`: `silent for {m:.0} min`.
- **A gate that cannot run.** `README.md:104`: "A gate that cannot run says so". `eval-gate.sh:10-15` exits silently, and parse failures are silent.
- **Other specs files.** `templates/claude-block.md:9`: other files under `specs/` "are never touched". `init-project.sh:31` ignores them.
- **Branch history.** `README.md:53`: specs "stay in the branch's history". That is lost on a squash-merge once the branch is deleted.

## 5. Top 5 changes

1. **(S)** Sanitise everything read from `state.md` and `.job/*` (integers only, never raw into `$(( ))`); ignore a tracked `state.md`; validate `dir`/`round` in `session-start.sh`.
2. **(S)** Gate the transition, not the turn end: `board set ... done` runs `check-evals --passed` and requires `Review: clean`; the hook clears `active`; `ready` cannot be set from `building`/`done`.
3. **(M)** Bind evidence to code: the tester writes `results.md` with the tested sha; the gate compares it to HEAD; the router runs the tester on the merged tree (and on fix branches) before the commit.
4. **(S)** Tool allowlists for reviewer and builder, `Agent(tester, reviewer)` for the worker, and a PreToolUse deny on Edit/Write of approved files for builder/worker/teammate.
5. **(M-L)** Collapse the three loop definitions into one (the worker runs the review-loop in its worktree); give team tickets a shared worktree or cut the mode; move runtime status out of tracked files.

## Not verified in round 1

- Harness behaviour the design depends on: SubagentStop `cwd` being the worktree; worktrees branching from local HEAD rather than `origin/HEAD`; `session_id` stability on resume; allowlist inheritance (`router.md:21`); the `agent_type` prefix under the `@skills-dir` install. (Round 2 tested these; see the design-changes appendix.)
- No live agent run of any flow. (Round 2 ran one single-feature flow.)
- `docs/superpowers/plans/2026-11-07-sa-core.md` was skimmed (header and deviation table only); `core/src/isotime.rs` and the bodies of `core/tests/` were not read.
