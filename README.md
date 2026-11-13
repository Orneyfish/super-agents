# super-agents

A Claude Code plugin that makes agents prove their work before calling it done, and lets you run many features in parallel while talking to one agent. It combines two workflows:

- **Verify before done** (the Claude Code team's review process): strict evals written first, build / test / review in separate fresh-context agents, strictness scaled to risk, loops that stop when they are not converging, a fast way back through git.
- **One agent to talk to** (DeepSeek's "super agent"): a router that only talks to you and hands tickets to workers, with a watchdog that notices stuck workers, a merger, a post-merge checker and a bug reproducer.

## Install

Needs `bash`, `git` and `curl`.

| Platform | Status |
|---|---|
| Linux (x86_64, arm64) | Supported: tested in CI and run live. |
| macOS 12.3 or newer (Intel, Apple silicon) | Supported: tested in CI (`macos-latest`). 12.3 is the minimum because the scripts use `readlink -f`; older versions were not tested. |
| Windows (x86_64) under Git Bash | Tested in CI only (the shell suite and the Rust tests); never run live, and the install steps below use `ln -s`. |
| Anything else (Windows on ARM, other CPUs, the BSDs) | No prebuilt `sa-core`: build it with cargo, or the hooks are off (each session names the platform). |

The ticket board and the hooks' JSON run on `sa-core`, a small native helper: the first time it is needed it is downloaded for your platform from this repo's GitHub release and checked against `dist/checksums/`, then again every time it runs (a cached copy that no longer matches is deleted and fetched again). `super-agents install-core` does that up front; `cargo build --release --manifest-path core/Cargo.toml` builds it from source instead; `SUPER_AGENTS_CORE=<path>` uses a binary you provide, and `SUPER_AGENTS_CORE_URL=<base URL>` downloads from a mirror, and `SUPER_AGENTS_CORE_TIMEOUT=<seconds>` caps each download attempt (default 20). After a failed download the hooks do not try again for 10 minutes; `super-agents install-core` retries at once. Without `sa-core` the hooks, including the done-gates, are switched off and let everything through; each session then says so.

**Claude Code** (everything works: skills, hooks, router and workers):

```bash
git clone https://github.com/Orneyfish/super-agents ~/Projects/super-agents
claude plugin marketplace add ~/Projects/super-agents     # a local path loads the repo in place, so your edits stay live
claude plugin install super-agents@super-agents
ln -s ~/Projects/super-agents/bin/super-agents      ~/.local/bin/super-agents
ln -s ~/Projects/super-agents/scripts/superagent.sh ~/.local/bin/superagent
super-agents install-core                                # downloads and verifies sa-core for this machine
```

Install it one way only, or the hooks would run twice. Alternatives: `claude plugin marketplace add Orneyfish/super-agents` installs from GitHub (a private repo needs working git credentials), and `ln -s ~/Projects/super-agents ~/.claude/skills/super-agents` loads it as an unregistered `@skills-dir` plugin. Update after pulling changes: `claude plugin update super-agents@super-agents`, then `/reload-plugins`. Remove: `claude plugin uninstall super-agents@super-agents`.

**Any other harness** (skills only, see the table): put the `super-agents` command on your PATH and link the skills into the folder your harness reads.

```bash
ln -s ~/Projects/super-agents/bin/super-agents ~/.local/bin/super-agents
super-agents install-core                                # downloads and verifies sa-core for this machine
super-agents link-skills ~/.agents/skills     # the universal Agent Skills folder (Codex, Gemini CLI, OpenCode, Copilot, ...)
super-agents link-skills ~/.hermes/skills     # Hermes Agent
# or: npx skills add Orneyfish/super-agents    (copies only skills/, so you still need the super-agents command above)
```

**Each project, once** (any harness): `super-agents setup` in the repo (Claude Code: `/super-agents:setup-project`). It adds `review.md`, a super-agents block in `CLAUDE.md` (and in `AGENTS.md` if one exists), and git-ignores run state. Re-running refreshes the block. Uninstall: remove the symlinks; each block sits between `SUPER_AGENTS_START` and `SUPER_AGENTS_END` markers.

## Harness support

| Harness | Skills | Done-gates (hooks) | Router, workers, watchdog | Verified |
|---|---|---|---|---|
| **Claude Code** | yes | yes | yes | End to end in live sessions: router, worker in a worktree, tester, reviewer, merger, checker; skills via the `super-agents` command; every gate and hook. Script assertions in `tests/run.sh`, run in CI on Linux and macOS. Agent **teams** (team-mode tickets) follow the docs but were not exercised live. |
| **Hermes Agent** | yes | no | no (use its own delegation) | All 8 skills discovered and enabled, and the command resolves from a clean login-shell PATH. A live model run was **not completed**: Hermes's configured Copilot provider failed to connect during testing. |
| **Codex CLI, Gemini CLI, OpenCode, Copilot, Cursor, and others that read Agent Skills (`.agents/skills`)** | expected | no | no | **Not tested** (not installed where this was built). Skills follow the Agent Skills format (name matches folder, description under 1,024 chars; checked by `tests/run.sh`) and call only the `super-agents` command, never a Claude-only variable. |

What degrades outside Claude Code: the hooks that stop an agent from saying "done" with failing evals, and the one that blinds the first-time-user agent, do not run, so the skills tell you to run `super-agents check-evals <dir> --passed` yourself. The router/worker system needs Claude Code's `--agent`, background subagents and worktree isolation; elsewhere use `write-tickets` to plan and the single-feature flow (`write-eval`, then `review-loop` with each role in a fresh session) to build.

## Two ways to build

**One feature, in this session:** `/super-agents:write-eval <name>` → you approve → `/super-agents:review-loop <name>`.

**Many features, in parallel:** `/super-agents:write-tickets <request or PRD>` → read the tickets → `/super-agents:mark-ready 001 002` → run `superagent` in a terminal and say "start with 001" (or just "start"). Workers build from the committed files of the branch you are on (`superagent` sets `worktree.baseRef` to `head` for its session; without it a worktree in a repository with a remote starts from the remote's default branch), so `superagent` first lists the uncommitted tickets, `review.md`, `CLAUDE.md` and `.gitignore` (your own unfinished edits to them included) and offers to commit them. A ticket you write or approve after `superagent` has started is not in new workers' worktrees until you run `super-agents commit-tickets` in a terminal (the router cannot run git; it will ask you to).

**Keeping specs out of your PRs:** `setup` git-ignores `specs/<name>/`, so single-feature specs are never committed (specs a project already tracks stay tracked). `specs/tickets/` must be committed while tickets run, so the router removes it for you: once the last ticket is `done` and the checker confirms it, the merger commits the removal of `specs/tickets/` on the integration branch (`super-agents drop-specs`; the files stay in the branch's history). You run nothing, and any other file under `specs/` is left alone. Tickets you add afterwards start a fresh board. Run `super-agents drop-specs` by hand only to retry, for example if the router session ended before it ran.

## Commands

| Command | What it does |
|---|---|
| `/super-agents:setup-project [path ...]` | Once per project: `review.md`, a super-agents block in `CLAUDE.md` (imports `review.md`, sets the git branch policy), git-ignores run state. Re-running refreshes the block. Takes several paths. |
| `/super-agents:classify-risk <feature>` | "What happens to a customer if this breaks?" gives low / medium / high. |
| `/super-agents:write-eval <feature>` | `specs/<feature>/RD.md` + `evals.md` (+ `mockup.html` for UI), validated, then stops for your review. |
| `/super-agents:write-tickets <request>` | Splits a request into tickets, interviews you one question at a time until nothing is left to guess, writes `specs/tickets/NNN-slug/{RD.md,evals.md}` and `BOARD.md`. |
| `/super-agents:mark-ready <NNN ...\|all\|dir>` | Your approval step: validates, then marks `draft` → `ready`. |
| `/super-agents:review-loop <feature\|NNN>` | Builder, tester, reviewer in rounds until every eval passes and review is clean. Max 5 rounds. |
| `/super-agents:first-time-user <feature>` | A subagent that cannot read the code uses the live app on a throwaway database and reports where it got stuck. |
| `/super-agents:fix-bug <problem>` | Reproduce, confirm the cause, fix at the root, add a regression test, use git to find or revert the breaking change. |
| `superagent` (terminal) | Starts the router for this project. Offers to create an `integration/<timestamp>` branch if you are on main. Enables agent teams for that session only. Runs with `--permission-mode auto` because workers run unattended (auto mode must be available to your account); pass your own `--permission-mode <mode>` to override. |

## The agents

| Agent | Role |
|---|---|
| `router` | The only agent you talk to. High effort, and **no write or shell tools**: it can only read, start agents and message them. Shows you a run plan and asks before it starts any tickets (name tickets to skip the question, or say "keep going" to stop being asked as more unblock), starts the watchdog, dispatches, checks each result against the ticket's evals, queues merges, relays decisions to you. |
| `worker` | One solo ticket in its own git worktree: builds, has the tester and reviewer check it, writes `results.md` + `evidence/`, commits on its branch. Sonnet. |
| `teammate` | One member of an agent team on a `team` ticket. Works in the main checkout on files it owns, agreed first in `contract.md`; the last-named teammate integrates and tests. |
| `merger` | Lands a solo branch, a team's work, or a fix branch on the current branch: merges without committing, runs lint + build, then commits or aborts; refuses a branch that changed the approved `evals.md`; marks the ticket done. One at a time. |
| `checker` | After a merge, walks the ticket and its neighbouring flows in a real browser on port 3000 as a first-time user. Fixes nothing (it has Bash, so that is a prompt rule). Reports only breaks it reproduced twice. |
| `reproducer` | Reproduces a bug twice in its own worktree; fixes it on its own branch if small and local; otherwise reports. |
| `watchdog` | Background. Runs a scan every 10 minutes and tells the router about silent, blocked or slow workers, dependency cycles, a down app. Rules live in `.super-agents/watchdog.conf`. |
| `tester` | Runs a ticket's evals exactly as written and returns PASS/FAIL with evidence. Uses `agent-browser` for browser checks, falls back to the Chrome tools. |
| `builder`, `reviewer` | The review-loop's fresh-context builder and reviewer (workers reuse the reviewer). Both have a `tools` allowlist: no Agent tool, no web tools, no MCP connectors except the reviewer's browser; the reviewer has no Edit or Write. |
| `first-time-user` | The blind newcomer used by the first-time-user skill. |

**Models, effort and turn limits** (the frontmatter of `agents/*.md`; `tests/run.sh` fails when this table and the files disagree):

| Agent | Model | Effort | maxTurns | Why |
|---|---|---|---|---|
| `router` | claude-fable-5-2 | high | none | The orchestrator: it decides what runs, reads every report and makes the acceptance call. It is your own session, so nothing caps its turns. |
| `worker` | sonnet | high | 200 | Does the building; a gate, a tester and a reviewer follow it. |
| `teammate` | sonnet | high | 200 | Same work as a worker, shared checkout. |
| `builder` | sonnet | default | 150 | The review-loop's build step; the tester and reviewer follow it every round. |
| `tester` | sonnet | default | 80 | Runs written checks literally; no judgement to buy with effort. |
| `reviewer` | sonnet | high | 80 | The independent check. Same model as the builder: independence comes from the fresh context only. |
| `merger` | sonnet | high | 60 | Resolves conflicts by hand and nothing reviews its result but lint and build. |
| `checker` | sonnet | default | 80 | Walks the app as a newcomer. |
| `reproducer` | sonnet | high | 120 | Has to find a cause, not only a symptom. |
| `watchdog` | sonnet | medium | 400 | Long-lived; forwards and summarises. |
| `first-time-user` | sonnet | default | none | Pinned so its cost does not depend on the model of the session that starts it. |

The turn limits are ceilings for an agent that loops, set well above anything seen so far (the one measured run, a toy feature, used 2-3 tool calls per agent); they are not tuned on real projects yet. A solo ticket costs at least five agent runs (worker, tester, reviewer, merger, checker) and up to four tester and four reviewer runs with three fix rounds; the router shows that total in its plan. There is no budget ceiling.

## Ticket folder

```
specs/tickets/BOARD.md                 # | # | Title | Status | Mode | Runs |
specs/tickets/001-slug/
  RD.md        # **Status:** draft|ready|building|done, **Risk:**, FR-/NFR- requirements, Touches, Must not touch, Decisions, Out of scope
  evals.md     # Setup, E1..En (check / pass when / fail when / covers), Definition of done. Approved by you; not edited while building
  .evals.sha256  # fingerprints of evals.md (line 1) and of RD.md without its Status line (line 2), written when you approve it (mark-ready; CRLF counts as LF, so Git's line-ending conversion on Windows does not matter); the done-gate fails if either file changes afterwards
  mockup.html  # UI tickets only
  contract.md  # team tickets: who owns which files, the names they share
  results.md   # written by the worker/tester: one row per eval, pass/fail, evidence path
  evidence/    # screenshots and output
```

Ticket `NNN` runs on port `3100+NNN` with test account `tNNN`; the main checkout is 3000 (`t000`) and the reproducer 3090 (`t090`). Change this in `review.md`.

## Hooks (Claude Code; always on while the plugin is enabled)

- **SessionStart**: states the "done means proven" agreement; in a git repo without `review.md` suggests `/super-agents:setup-project`; mentions an active loop or a ticket board.
- **Stop**: while a review-loop is active (and no subagent of the session is still running: a stop then is a wait and passes unchecked), blocks "done" until every eval passes in `results.md`, each pass row pointing at a non-empty `evidence/` file, and `evals.md` matches the fingerprint written when you approved it (no fingerprint counts as a failure; re-approve with `mark-ready`). Only the session that started the loop is gated by it (its id is the `session:` line of `.super-agents/state.md`, recorded by the review-loop); other sessions in the repo never are. A state file without that line falls back to the first session that stops, which an unrelated session can be. Released when the loop waits on you, when the state file is over 12 hours old, or after 3 blocks.
- **SubagentStop**: a worker cannot finish until the same holds (or it declared itself blocked, or stopped to ask you something (phase `waiting`), or after 3 blocks; going back to `building` resets the count). A gate that cannot run says so. Teammates on team tickets are not gated: their tickets rely on the integrator's tester run and the router's read of the results.
- **PreToolUse**: keeps only the first-time-user agent away from the code (Bash denylist, and `file:` URLs in browser calls).

## Known limits

- **Team tickets use Claude Code's experimental agent teams**, which `superagent` enables for its own session only. They only work in an interactive session, are not resumable, and teammates share the main checkout (hence the file-ownership contract).
- The router restriction is its `tools` list, so it cannot start servers or run `super-agents board`; workers, the merger and the watchdog do that.
- `agent-browser` is not bundled. Install it for parallel browser checks: `npm install -g agent-browser && agent-browser install`. Without it the tester, checker and reproducer fall back to the Chrome tools, which are one shared browser.
- The done-gates check that evidence files exist and are non-empty, not what they show. In a worker's worktree the `evals.md` fingerprint is checked against the copy in your main checkout. Nothing technical stops a worker from writing there (workers have Bash), so the router reads `evals.md` from the main checkout and the merger refuses a branch that changed the approved files. In the single-feature review-loop the builder shares your checkout, so there the fingerprint only catches accidental edits. The post-merge checker, which re-walks the merged feature in a browser, is the independent check.
- **Parallel mode runs unattended** (`--permission-mode auto`) and the worker, merger, reproducer and teammates have Bash. "Never push", "never touch the main checkout" and "never edit `evals.md`" are prompt rules. On a real codebase run it in a container, a VM or a disposable clone.
- The first-time-user Bash block is a regex denylist, not a sandbox: it blocks file-reading commands and shell wrappers where a command starts (words inside arguments are fine; a plain filter such as `head -5` or `grep ok` after a pipe from `curl` or a launcher is fine too, but a filter given a file (`head main.py`, `grep ok app.py`, `grep -f`, `grep -r`, `< file`) is not: any operand beyond the one pattern, script or program of `grep`, `sed` and `jq` counts as a file), and `file:` URLs in browser calls. A determined agent can still bypass it, for example by splitting a word with quotes.
- Plugin subagents cannot carry their own hooks, so the worker and first-time-user gates are plugin-level hooks keyed on `agent_type`.
- Parallel agents and router sessions are expensive. Use tickets for work that is worth it, and `classify-risk` to decide how hard to push.

## Development

`bash tests/run.sh` runs the script tests plus consistency checks (manifest versions, hook scripts exist and are executable, agent names match their files, every `super-agents:<name>` reference resolves). It needs `git` and a Rust toolchain (1.89 or newer; it builds `core/` first), fails if any script calls `jq` or Python, and runs on Linux and macOS. `cd core && cargo test` runs the Rust tests, on Windows too.

- **CI** (`.github/workflows/ci.yml`): the tests on Linux and macOS, ShellCheck on Linux, and `cargo fmt`, `clippy` and `cargo test` for `core/` (the Rust tests also on Windows), for every push and pull request.
- **Release:** bump the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `core/Cargo.toml`; run `gh workflow run build-core.yml --ref <branch> -f version=X.Y.Z`, which builds sa-core for five platforms into a draft release; commit its checksums with `gh release download vX.Y.Z -p checksums.txt -O dist/checksums/vX.Y.Z.txt`; then push the tag `vX.Y.Z`. `release.yml` also refuses to publish when `core/` at the tag differs from the commit the binaries were built from (re-run `build-core.yml` then), and asks the released Linux binary for its version. `release.yml` re-runs ShellCheck and the tests, checks the draft's binaries against the committed checksums, and publishes. Merge to `main` after it is published, so installs never see a version whose binaries are not downloadable.
- **Local gate** (optional): `git config core.hooksPath .githooks` runs the tests before every `git push`.

The agents and skills are prompts, so the checks above cannot test them. `evals/` holds model-run cases for `classify-risk` (including whether it fires from a plain question) and `write-eval` (writes a draft spec and builds nothing). Run them by hand, not in CI, since they cost about $2 on your credential: `claude plugin eval . --allow-tools Write Edit --ablation none --no-publish --max-cost-usd 3`. They run without `Bash`, so they cannot exercise the skills' `super-agents` validation steps. The router, workers, merger and team mode have no automated test and still need a live run.
