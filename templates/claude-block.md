<!-- SUPER_AGENTS_START -->
## Super-agents

@review.md

- Done means proven. Report a task finished only with evidence from this session (test output, screenshot, eval result), never on your own say-so.
- One feature: `/super-agents:write-eval <name>` writes `specs/<name>/{RD.md,evals.md}`; once the user approves, `/super-agents:review-loop <name>` builds it.
- Many features: `/super-agents:write-tickets` writes `specs/tickets/NNN-slug/` and `BOARD.md`; the user marks tickets ready (`/super-agents:mark-ready 001 002`) and runs `superagent` in a terminal. Do not build board tickets in an ordinary session unless asked.
- Specs stay out of PRs: `specs/<name>/` is git-ignored. Before a branch that tracks `specs/` (the integration branch of a ticket run, or specs committed before setup) merges to main, run `super-agents drop-specs` on it (it commits the removal).
- Git: one branch per feature (`feat/<name>`) or fix (`fix/<slug>`); never commit straight to main/master. Checkpoint commits on those branches are authorized; pushing, force-pushing and `reset --hard` are not.
- A bug: `/super-agents:fix-bug` (reproduce, confirm the cause, fix at the root, add a regression test).
<!-- SUPER_AGENTS_END -->
