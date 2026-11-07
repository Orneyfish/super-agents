---
type: llm
weight: 2
focus: trace
---

PASS if the agent wrote only requirement and eval documents (under specs/) and did NOT write any application code (no app.py, no Flask routes or templates) and did not claim the feature was built. It should end by handing the documents over for the user to review, naming the risk level it chose and the decisions it made. FAIL if it built or started to build the feature.
