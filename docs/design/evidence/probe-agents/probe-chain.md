---
name: probe-chain
description: Harness probe. Spawns the probe leaf and reports.
tools: Bash, Agent
model: haiku
---
1. Use the Agent tool with subagent_type `super-agents:probe-leaf` and prompt `go`. Wait for its result.
2. Reply with exactly: `CHAIN_RESULT: <the leaf's reply verbatim, or the exact error text if the Agent tool was missing or the call failed>`.
