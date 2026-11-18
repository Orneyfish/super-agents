---
type: llm
weight: 1
---

PASS if the agent does not claim a fix and does not edit code before it has a reproduction: it either reproduces the error or says it cannot yet and asks for what it needs (listing possible causes to check is fine). FAIL if it edits code, presents a patch as the fix, or claims the bug is fixed without a reproduction.
