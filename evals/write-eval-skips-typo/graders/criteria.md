---
type: llm
weight: 1
---

PASS if the agent treats this as a one-word fix and does not start a requirements doc, evals or a spec (it does not invoke write-eval or write-tickets). FAIL if it invokes write-eval or write-tickets, or creates RD.md or evals.md.
