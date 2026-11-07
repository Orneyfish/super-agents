# super-agents

A Claude Code plugin that makes agents prove their work before calling it done, and lets you run many features in parallel while talking to one agent. It combines two workflows:

- **Verify before done** (the Claude Code team's review process): strict evals written first, build / test / review in separate fresh-context agents, strictness scaled to risk, loops that stop when they are not converging, a fast way back through git.
- **One agent to talk to** (DeepSeek's "super agent"): a router that only talks to you and hands tickets to workers, with a watchdog that notices stuck workers, a merger, a post-merge checker and a bug reproducer.

## Install

**Claude Code** (everything works: skills, hooks, router and workers):

```bash
git clone https://github.com/Orneyfish/super-agents ~/Projects/super-agents
ln -s ~/Projects/super-agents ~/.claude/skills/super-agents        # loads as super-agents@skills-dir in every session
# or as a marketplace plugin instead (do not do both, the hooks would run twice):
#   /plugin marketplace add Orneyfish/super-agents   then   /plugin install super-agents@super-agents
ln -s ~/Projects/super-agents/bin/super-agents  ~/.local/bin/super-agents
ln -s ~/Projects/super-agents/scripts/superagent.sh ~/.local/bin/superagent
```

**Any other harness** (skills only, see the table): put the `super-agents` command on your PATH and link the skills into the folder your harness reads.

```bash
ln -s ~/Projects/super-agents/bin/super-agents ~/.local/bin/super-agents
super-agents link-skills ~/.agents/skills     # the universal Agent Skills folder (Codex, Gemini CLI, OpenCode, Copilot, ...)
super-agents link-skills ~/.hermes/skills     # Hermes Agent
# or: npx skills add Orneyfish/super-agents    (copies only skills/, so you still need the super-agents command above)
```

**Each project, once** (any harness): `super-agents setup` in the repo (Claude Code: `/super-agents:setup-project`). It adds `review.md`, a super-agents block in `CLAUDE.md` (and in `AGENTS.md` if one exists), and git-ignores run state. Re-running refreshes the block. Uninstall: remove the symlinks; each block sits between `SUPER_AGENTS_START` and `SUPER_AGENTS_END` markers.

## Harness support

| Harness | Skills | Done-gates (hooks) | Router, workers, watchdog | Verified |
|---|---|---|---|---|
| **Claude Code** | yes | yes | yes | End to end in live sessions: router, worker in a worktree, tester, reviewer, merger, checker; skills via the `super-agents` command; every gate and hook. 97 script assertions (`tests/run.sh`). Agent **teams** (team-mode tickets) follow the docs but were not exercised live. |
| **Hermes Agent** | yes | no | no (use its own delegation) | All 8 skills discovered and enabled, and the command resolves from a clean login-shell PATH. A live model run was **not completed**: Hermes's configured Copilot provider failed to connect during testing. |
| **Codex CLI, Gemini CLI, OpenCode, Copilot, Cursor, and others that read Agent Skills (`.agents/skills`)** | expected | no | no | **Not tested** (not installed where this was built). Skills follow the Agent Skills format (name matches folder, description under 1,024 chars; checked by `tests/run.sh`) and call only the `super-agents` command, never a Claude-only variable. |

What degrades outside Claude Code: the hooks that stop an agent from saying "done" with failing evals, and the one that blinds the first-time-user agent, do not run, so the skills tell you to run `super-agents check-evals <dir> --passed` yourself. The router/worker system needs Claude Code's `--agent`, background subagents and worktree isolation; elsewhere use `write-tickets` to plan and the single-feature flow (`write-eval`, then `review-loop` with each role in a fresh session) to build.

## Two ways to build

**One feature, in this session:** `/super-agents:write-eval <name>` → you approve → `/super-agents:review-loop <name>`.

**Many features, in parallel:** `/super-agents:write-tickets <request or PRD>` → read the tickets → `/super-agents:mark-ready 001 002` → run `superagent` in a terminal and say "start with 001" (or just "start").

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
| `superagent` (terminal) | Starts the router for this project. Offers to create an `integration/<timestamp>` branch if you are on main. Enables agent teams for that session only. |

## The agents

| Agent | Role |
|---|---|
| `router` | The only agent you talk to. Opus, high effort, and **no write or shell tools**: it can only read, start agents and message them. Starts the watchdog first, dispatches runnable tickets, checks each result against the ticket's evals, queues merges, relays decisions to you. |
| `worker` | One solo ticket in its own git worktree: builds, has the tester and reviewer check it, writes `results.md` + `evidence/`, commits on its branch. Sonnet. |
| `teammate` | One member of an agent team on a `team` ticket. Works in the main checkout on files it owns, agreed first in `contract.md`; the last-named teammate integrates and tests. |
| `merger` | Lands a solo branch, a team's work, or a fix branch on the current branch; lint + build; undoes on failure; marks the ticket done. One at a time. |
| `checker` | After a merge, walks the ticket and its neighbouring flows in a real browser on port 3000 as a first-time user. Read-only. Reports only breaks it reproduced twice. |
| `reproducer` | Reproduces a bug twice in its own worktree; fixes it on its own branch if small and local; otherwise reports. |
| `watchdog` | Background. Runs a scan every 10 minutes and tells the router about silent, blocked or slow workers, dependency cycles, a down app. Rules live in `.super-agents/watchdog.conf`. |
| `tester` | Runs a ticket's evals exactly as written and returns PASS/FAIL with evidence. Uses `agent-browser` for browser checks, falls back to the Chrome tools. |
| `builder`, `reviewer` | The review-loop's fresh-context builder and read-only reviewer (workers reuse the reviewer). |
| `first-time-user` | The blind newcomer used by the first-time-user skill. |

## Ticket folder

```
specs/tickets/BOARD.md                 # | # | Title | Status | Mode | Runs |
specs/tickets/001-slug/
  RD.md        # **Status:** draft|ready|building|done, **Risk:**, FR-/NFR- requirements, Touches, Must not touch, Decisions, Out of scope
  evals.md     # Setup, E1..En (check / pass when / fail when / covers), Definition of done. Approved by you; not edited while building
  mockup.html  # UI tickets only
  contract.md  # team tickets: who owns which files, the names they share
  results.md   # written by the worker/tester: one row per eval, pass/fail, evidence path
  evidence/    # screenshots and output
```

Ticket `NNN` runs on port `3100+NNN` with test account `tNNN`; the main checkout is 3000 (`t000`) and the reproducer 3090 (`t090`). Change this in `review.md`.

## Hooks (Claude Code; always on while the plugin is enabled)

- **SessionStart**: states the "done means proven" agreement; in a git repo without `review.md` suggests `/super-agents:setup-project`; mentions an active loop or a ticket board.
- **Stop**: while a review-loop is active, blocks "done" until every eval passes in `results.md`. Released when the loop waits on you, when the state file is over 12 hours old, or after 3 blocks.
- **SubagentStop**: a worker cannot finish until every eval has a pass row with its evidence file (or it declared itself blocked, or after 3 blocks).
- **PreToolUse**: keeps only the first-time-user agent away from the code.

## Known limits

- **Team tickets use Claude Code's experimental agent teams**, which `superagent` enables for its own session only. They only work in an interactive session, are not resumable, and teammates share the main checkout (hence the file-ownership contract).
- The router restriction is its `tools` list, so it cannot start servers or run `board.py`; workers, the merger and the watchdog do that.
- `agent-browser` is not bundled. Install it for parallel browser checks: `npm install -g agent-browser && agent-browser install`. Without it the tester, checker and reproducer fall back to the Chrome tools, which are one shared browser.
- The first-time-user Bash block is a regex denylist, not a sandbox.
- Plugin subagents cannot carry their own hooks, so the worker and first-time-user gates are plugin-level hooks keyed on `agent_type`.
- Parallel agents and router sessions are expensive. Use tickets for work that is worth it, and `classify-risk` to decide how hard to push.
