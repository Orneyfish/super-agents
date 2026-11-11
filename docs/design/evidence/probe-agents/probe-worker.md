---
name: probe-worker
description: Harness probe that runs in its own git worktree.
tools: Read, Bash, Edit, Write, Agent
model: haiku
isolation: worktree
---
You are a harness probe. Do every step in order, one tool call per step, and never skip a step even if an earlier one failed. Run each Bash command on its own, exactly as written.
1. Bash: `pwd`
2. Bash: `git rev-parse HEAD`
3. Bash: `git branch --show-current`
4. Bash: `git log --oneline -4`
5. Bash: `command -v super-agents`
6. Write tool: create `probe-worker-note.txt` in your current directory with the content `w1`.
7. Edit tool: in that file replace `w1` with `w2`.
8. Write tool: create `protected.txt` in your current directory with the content `worker`. If the tool is refused, note the exact refusal text and go on.
9. Bash: `git merge --ff-only probe/prev`
10. Bash: `git log --oneline -4`
11. Agent tool: subagent_type `super-agents:probe-leaf`, prompt `go`. If you have no Agent tool or the call fails, note the exact error.
Final reply: a numbered list, one line per step, with the exact output or error of that step. Do not summarise.
