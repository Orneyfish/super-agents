# Review rules

Read by the super-agents reviewer and by `/code-review`. Keep it short and specific to this project; delete what does not apply.

## What counts as a failure
- Behaviour differs from `specs/<feature>/RD.md` or from an eval in `specs/<feature>/evals.md`.
- Data loss, wrong data shown, or one user able to see or change another user's data.
- A crash, unhandled error, or silent failure on a path a user can actually reach.
- A missing or bypassable auth/permission check; a secret in code, logs or a response.
- UI that does not match `specs/<feature>/mockup.html` at desktop or mobile width.
- Not code (delete what does not apply): an unsupported claim; a number that does not reproduce; a required part that is missing; content nobody asked for; a step that was described but not run.
- TODO: add this project's own failures (money, PII, migrations, external APIs, ...).

## Severity
- **blocker**: a user loses data/money/access, sees someone else's data, or the feature does not work.
- **major**: a reachable path breaks or misbehaves, but nothing is lost and a retry works.
- **minor**: cosmetic, wording, or an unlikely edge.
- Not code: **blocker** = a required part is missing, a number does not reproduce, a quote is not at its source, or a reader would act on something false; **major** = an unsupported claim, a dead link, or a step described but not run; **minor** = phrasing or layout.
- Done requires: no open blocker or major (high-risk features: no open minor on auth/data paths either).

## Ignore
- Formatting, naming taste, and anything a linter already enforces.
- Theoretical problems with no reachable path.
- Code the change did not touch, unless the change made it reachable.

## Report format
One line per finding: `F<n> [severity] [class] file:line - what is wrong - how to reproduce`. For a document the location is `file: section` instead of `file:line`.
`class` names the kind of mistake, not the instance (e.g. `missing-auth-check`, `unhandled-empty-state`, `off-by-one`, `n-plus-one-query`), so it can be fixed everywhere it occurs.
Only report what you can show with evidence. Nothing found: write `no findings`.

## How to test this project
- TODO: run command, test command, lint and build commands, how to start the app on a chosen port with its own temporary database / data dir, how to create a test account.
- Pre-merge checks: TODO commands run before work is merged (lint and build for code; a link or style check for documents), or none.
- Ports and accounts (change here if your app needs different ones): main checkout 3000 (account t000); bug reproducer 3090 (t090); ticket NNN on port 3100+NNN (account tNNN), so parallel tickets never share state.

## Rules learned over time
<!-- One line each. Add when a review missed a bug that surfaced later, or flagged the same non-problem more than once. -->
