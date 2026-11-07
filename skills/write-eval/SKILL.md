---
name: write-eval
description: Turn a feature idea into a written requirements doc plus strict evals (and a mockup for UI features) that the user reviews BEFORE any code is built. Use when the user wants to add or change user-visible behaviour, or says "spec this", "write evals", "define done". Not for typo or one-line changes, and not for bug fixes (use fix-bug). For several features at once use write-tickets.
argument-hint: <feature-name> [low|medium|high]
---

Evals are the fixed tests that decide whether work is done. Write them before building, make them strict enough that lazy work fails, and get the user to approve them. Do not write feature code in this skill.

Feature name = first word of "$ARGUMENTS" in kebab-case. Directory = `specs/<feature>/` (write-tickets passes a ticket directory instead).

1. **Requirements.** If `RD.md` is missing, draft it from the conversation using the template printed by `super-agents template RD.md`: summary, user stories, `FR-n` functional requirements (each one observable behaviour, testable on its own; names that other work relies on written out in full), `NFR-n`, what the feature **touches**, what it **must not touch**, every **decision** made while writing it, **out of scope**, and `UI: yes|no`. Status starts `draft`. If `RD.md` exists, tighten it; never silently drop a requirement.
2. **Risk.** Use the second argument if given, otherwise run the `super-agents:classify-risk` skill on the feature. It sets the `**Risk:**` line in `RD.md`.
3. **Evals.** Create `evals.md` from the template printed by `super-agents template evals.md` and fill it in: a Setup section, one `## E<n>` block per check, and the Definition of done. Strictness follows risk:
   - low: a happy-path eval per requirement, plus one failure-mode eval for the riskiest one.
   - medium: per requirement a happy path and at least one error or edge case (empty, invalid, duplicate, retry, state after reload).
   - high: all of medium, plus abuse and safety evals: another user cannot read or change this data, no double-charge or lost write on retry, a failure midway leaves consistent state, hostile input, a rollback path.
   Every eval needs a concrete `check` that someone who has never seen the code can run, a `pass when`, and a `fail when` naming what a stub or lazy implementation would show; `covers:` lists the `FR-`/`NFR-` ids it proves. If a stub could pass an eval, rewrite it. Prefer automated checks (a test command, curl, a script); use browser steps only for UI, and then reference `mockup.html` at desktop and ~390px. Setup always gives the feature its own port, its own data directory and a test account, never real data.
4. **Mockup** (only if `UI: yes`). Write `mockup.html`: one self-contained static file, inline CSS, no build. Show every state the requirements imply (default, empty, loading, error, success, others) labelled, and the layout at desktop width and at ~390px. Reuse the project's existing look if it has one. It is a design reference for the tester to compare against, not a working app.
5. **Validate, then attack your own work.** Run `super-agents check-evals <dir>` and fix until it prints `OK`. Then reread every eval as an adversary and ask whether a stub could pass it; fix and rerun.
6. **Hand over.** Status stays `draft`. Tell the user the file paths (open `mockup.html` with `xdg-open` if present), the risk level you chose and why, and every decision you made on your own (assumptions, scope cuts, anything ambiguous). Say what to review: `RD.md`, `evals.md` and the mockup. Outcomes of a build go in `results.md`; these two files are not edited while building.
7. **Stop.** Build nothing. If the user asks for changes, edit, rerun the check, stay `draft`. When the user explicitly approves, run `super-agents board set <dir> ready` and tell them to run `/super-agents:review-loop <feature>`.
