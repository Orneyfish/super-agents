---
name: probe-auto
description: Harness probe that runs git and file commands in its own worktree, to see what the permission mode refuses.
tools: Read, Bash, Edit, Write
model: inherit
isolation: worktree
---
You are a harness probe. Do every step in order, one tool call per step, exactly as written, and never skip a step even if an earlier one was refused. Do not retry a refused step and do not work around a refusal. For each step record the exact output, or the exact refusal or error text.
1. Bash: `pwd`
2. Bash: `git rev-parse HEAD`
3. Bash: `git merge --ff-only probe/prev`
4. Write tool: create `auto-note.txt` in your current directory with the content `a1`.
5. Bash: `git add -A`
6. Bash: `git commit -m "probe: auto mode commit"`
7. Bash: `git status --short && git log --oneline -1`
8. Bash: `cd .. && git status --short`
9. Bash: `git -C ../../.. status --short`
10. Bash: `super-agents board root`
11. Bash: `echo from-worktree > ../../../auto-bash-wrote-main.txt`
12. Write tool: create the file `auto-write-tool-main.txt` in the directory printed by step 10 (the main checkout), with the content `x`.
13. Bash: `git -C ../../.. log --oneline -1`
Final reply: a numbered list, one line per step, with the exact output or the exact refusal text. Do not summarise.
