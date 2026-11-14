---
name: fix-bug
description: 'Find and fix the root cause of a bug: reproduce it, confirm the cause, fix once in shared code, prove it with a regression test, and use git history to locate or roll back the breaking change. Use for "X is broken", "this stopped working", errors and regressions.'
argument-hint: <what is wrong and how you saw it>
---

# Fix bug

Bug: "$ARGUMENTS". No fix before a reproduction and a confirmed cause.

## Instructions

1. **Branch.** Work on `fix/<short-slug>` (or the feature branch the bug belongs to). Never on main/master.
2. **Reproduce.** "Reproduced" means one command you already ran that goes red on this bug, ideally a failing test (use the project's test setup). Then minimise it: cut steps and inputs until the smallest case still goes red. If you cannot reproduce it after real attempts, stop and say so; do not fix blind.
3. **Find the cause.** List at least three candidate causes, ranked by likelihood, each with the prediction that would confirm it (what the probe shows if this is the cause). For each, pick the cheapest probe that tells them apart (a log line, an assertion, a test, `git log -S'<symbol>'`). Run it. A cause is confirmed only when a probe distinguishes it from the others. Tag every piece of instrumentation you add (for example `DEBUG-FIXBUG`) so one grep finds it; remove all of it before you commit. For a regression, `git bisect run <repro>` between the last good commit and the bad one; the culprit commit is evidence, not yet the root cause.
4. **Fix at the root.** Grep every caller and sibling of the faulty code and every other instance of the same kind of mistake; fix it once in shared code. Keep the validation and error handling of any code you move.
5. **Prove it.** The reproduction now passes. Run the relevant existing tests. If `specs/*/evals.md` covers the area, rerun those evals too. Keep the repro as a regression test.
6. **Commit** on the fix branch, only the files you changed (no `git add -A`: changes that were already uncommitted are the user's), after `grep` for your instrumentation tag finds nothing: the message names the cause and the test. Never push.
7. **Rollback option.** If the culprit is a whole commit or feature and a small forward fix is not clear, offer `git revert <sha>` (a new commit that undoes it). Do it only with the user's approval. Never `reset --hard` or force-push.
8. **Report:** symptom, confirmed cause with the probe that confirmed it, the fix, the test, and anything you did not check.

**Work that is not code** (a document, a data analysis, a procedure). The reproduction is the check that shows the error: rerun the script, open the source and find the passage, follow the runbook step. Fix at the root (the data, the template, the source list), not the one wrong output, and keep the check so the error cannot return. `templates/kinds.md` (`super-agents template kinds.md`) lists the checks for each kind.

## Examples

Request: `/fix-bug login fails with a 500 when the email has a capital letter`.
The skill works on `fix/login-email-case`, writes a failing test that sends `Ada@Example.com` and sees it go red, and ranks three candidate causes with a probe for each. The probe confirms that the lookup is case-sensitive. It fixes the shared `normalizeEmail` helper once, so signup and password reset get the fix too.
It reruns the tests, keeps the repro as a regression test, and commits only the files it changed with a message naming the cause and the test. It does not push.
