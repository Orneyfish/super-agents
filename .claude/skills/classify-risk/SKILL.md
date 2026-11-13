---
name: classify-risk
description: Rate a feature or change low, medium or high risk by asking what happens to a customer if it breaks. Use before write-eval or review-loop, or when the user asks how carefully something needs reviewing.
argument-hint: <feature or change description>
---

Ask one question about "$ARGUMENTS": **what happens to a customer if this breaks?** Rate the worst realistic failure, not the likely one.

- **low**: it only looks wrong (layout, copy, colour). Everything still works.
- **medium**: a feature stops working, but nobody loses anything and it can be fixed later. Data is intact.
- **high**: a customer can lose money, get locked out, lose or corrupt data, or see another person's data, and it cannot be taken back. Anything touching auth, payments, permissions, deletes, migrations or personal data is high until shown otherwise.

If the call is between two levels, take the higher. If you cannot tell what the change touches, read the spec or the diff first; do not guess from the name.

If the feature's `RD.md` exists, set its `**Risk:**` line to the level (add it under `**Status:**` if missing). Do this silently; with no `RD.md` there is nothing to do.

Your whole reply is this one line: `RISK: <level> - <the worst realistic customer impact>`.

The level sets how hard everything downstream works: write-eval adds more adversarial evals as it rises, and the reviewer reports lower severities as it rises.
