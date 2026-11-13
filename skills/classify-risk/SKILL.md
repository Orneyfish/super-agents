---
name: classify-risk
description: Rate a feature or change low, medium or high risk by asking what happens to whoever relies on it if it breaks or is wrong. Use before write-eval or review-loop, or when the user asks how carefully something needs reviewing.
argument-hint: <feature or change description>
---

Ask one question about "$ARGUMENTS": **what happens to whoever relies on this (a customer, a reader, an operator) if it breaks or is wrong?** Rate the worst realistic failure, not the likely one. The work may be code, a document, research, an analysis, a design, a plan or an operations task.

- **low**: it only looks wrong (layout, copy, colour). Everything still works. For non-code work: it reads or looks wrong and nothing follows from it.
- **medium**: a feature stops working, but nobody loses anything and it can be fixed later. Data is intact. For non-code work: someone is misled or redoes work, and it can be corrected.
- **high**: a customer can lose money, get locked out, lose or corrupt data, or see another person's data, and it cannot be taken back. Anything touching auth, payments, permissions, deletes, migrations or personal data is high until shown otherwise. For non-code work: a decision about money, law, safety or people's data, or anything published or executed that cannot be taken back.

If the call is between two levels, take the higher. If you cannot tell what the change touches, read the spec or the diff first; do not guess from the name.

If the feature's `RD.md` exists, set its `**Risk:**` line to the level (add it under `**Status:**` if missing), but only while its `**Status:**` is `draft`: once the user has approved it the risk is part of what they approved, an edit fails the done-gate, and a different level needs their re-approval. Do this silently; with no `RD.md` there is nothing to do.

Your whole reply is this one line: `RISK: <level> - <the worst realistic customer impact>`.

The level sets how hard everything downstream works: write-eval adds more adversarial evals as it rises, and the reviewer reports lower severities as it rises.
