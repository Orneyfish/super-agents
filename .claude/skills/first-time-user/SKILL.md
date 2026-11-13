---
name: first-time-user
description: Have a fresh agent that has never seen the code use the live app like a first-time customer and report every place it gets stuck. Run after a feature passes review-loop, or any time an outside view of the UX is wanted.
argument-hint: <feature-or-flow> [goal in plain words]
disable-model-invocation: true
---

The builder and you both know how the feature is meant to work, so you will miss what a newcomer trips on. Send in someone who does not know.

This is for live apps only; a document is checked by the reader test in its evals, because this agent cannot read files.

**Harness note.** `super-agents:first-time-user` is the definition in `agents/first-time-user.md`. Outside Claude Code, start a fresh session with that file's body as its instructions; the code-read block is a Claude Code hook, so elsewhere it is only the agent's own rule, and you should not give it a project directory to browse.

1. **How to run it.** You may read the code, README and scripts to find the start command, port and how to point the app at a throwaway database or data directory. The subagent may not.
2. **Sandbox.** `sandbox=$(mktemp -d)`. Start the app (Bash with `run_in_background`) against a temporary database or data dir inside it, seeded with only what the flow needs. If you cannot find a setting that guarantees real data is untouched, stop and ask the user; never run this against real data. Wait until the app answers (poll with curl).
3. **Brief the agent** with `super-agents:first-time-user`, giving it only: the URL (or, for a command-line app, the path to a small launcher script inside the sandbox), and the goal in the user's plain words ("sign up and add your first expense"). Leave out file names, stack, requirement ids and anything from `specs/`. A PreToolUse hook blocks that agent from reading code; Bash blocking is a best-effort denylist.
4. **Clean up.** After it returns, stop the app and `rm -rf "$sandbox"` (check it is the mktemp path first).
5. **Report** its friction list, most severe first, with suggested fixes. Change nothing without the user's go-ahead. A fix that changes what the feature should do goes back through `/super-agents:write-eval`; a plain defect goes through `/super-agents:fix-bug`.
