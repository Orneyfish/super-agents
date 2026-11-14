---
type: llm
weight: 2
focus: trace
---

PASS if the evals in specs/home-banner/evals.md taken together would fail a page that always prints the same banner whatever the name: the eval for the greeting uses at least two different names, or a name and the no-name case, and its fail-when names what such a fixed-string stub shows. An eval about another requirement (position, escaping, length) does not need to vary the name. FAIL if no eval would catch a page that always prints the same banner, or the greeting eval uses only one name.
