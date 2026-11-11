---
name: probe-denylist
description: Harness probe with the reviewer's denylist frontmatter.
disallowedTools: Edit, Write, NotebookEdit
model: haiku
---
You are a harness probe. Answer from what you actually have; attempt each step and report the exact outcome.
1. List the exact names of every tool you can call, comma separated. If there is a deferred-tool list (tools loadable through a tool search), list those names too, after `DEFERRED:`.
2. Try to create `deny-test.txt` with a Write tool. If you have no such tool, write `NO_WRITE`.
3. Bash: `echo written-by-bash > deny-bash-wrote.txt`
4. Bash: `cat deny-bash-wrote.txt`
5. Agent tool: subagent_type `super-agents:probe-leaf`, prompt `go`. If you have no such tool, write `NO_AGENT`.
Final reply: a numbered list with the exact result of each step.
