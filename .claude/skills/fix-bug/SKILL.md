---
name: fix-bug
description: Find and fix the root cause of a bug: reproduce it, confirm the cause, fix once in shared code, prove it with a regression test, and use git history to locate or roll back the breaking change. Use for "X is broken", "this stopped working", errors and regressions.
argument-hint: <what is wrong and how you saw it>
---

Bug: "$ARGUMENTS". No fix before a reproduction and a confirmed cause.

1. **Branch.** Work on `fix/<short-slug>` (or the feature branch the bug belongs to). Never on main/master.
2. **Reproduce.** Find the smallest exact steps, ideally a failing test (use the project's test setup), and run it until you watch it fail. If you cannot reproduce it after real attempts, stop and say so; do not fix blind.
3. **Find the cause.** List at least two candidate causes. For each, pick the cheapest probe that tells them apart (a log line, an assertion, a test, `git log -S'<symbol>'`). Run it. A cause is confirmed only when a probe distinguishes it from the others. For a regression, `git bisect run <repro>` between the last good commit and the bad one; the culprit commit is evidence, not yet the root cause.
4. **Fix at the root.** Grep every caller and sibling of the faulty code and every other instance of the same kind of mistake; fix it once in shared code. Keep the validation and error handling of any code you move.
5. **Prove it.** The reproduction now passes. Run the relevant existing tests. If `specs/*/evals.md` covers the area, rerun those evals too. Keep the repro as a regression test.
6. **Commit** on the fix branch: the message names the cause and the test. Never push.
7. **Rollback option.** If the culprit is a whole commit or feature and a small forward fix is not clear, offer `git revert <sha>` (a new commit that undoes it). Do it only with the user's approval. Never `reset --hard` or force-push.
8. **Report:** symptom, confirmed cause with the probe that confirmed it, the fix, the test, and anything you did not check.
