---
name: probe-router
description: Harness probe with a router-style scoped Agent allowlist.
tools: Read, Agent(super-agents:probe-mid, super-agents:probe-leaf, super-agents:probe-chain, super-agents:probe-worker)
model: haiku
---
You are a harness probe. Do every step in order, in the foreground (never in the background), and never skip a step even if an earlier one failed.
1. Agent tool: subagent_type `super-agents:probe-mid`, prompt `go`. Wait for its result.
2. Agent tool: subagent_type `super-agents:probe-leaf2`, prompt `go`. Note the reply or the exact error text.
3. Agent tool: subagent_type `super-agents:probe-worker`, prompt `go`. Wait for its result.
4. Try to use a Bash tool to run `pwd`. If you have no such tool, say `NO_BASH_TOOL`.
Final reply: `MID_REPLY:` followed by probe-mid's reply verbatim; then `STEP2:` and the result of step 2; then `WORKER_REPLY:` and probe-worker's reply verbatim; then `STEP4:` and its result; then a line starting `AGENT_TYPES:` listing every agent type your Agent tool says is available, verbatim.
