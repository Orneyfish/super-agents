---
name: setup-project
description: Set up the current project (or a list of project paths) for super-agents. Adds review.md, the git/branch policy and review.md import to CLAUDE.md, and ignores the loop's state dir. Run once per project.
argument-hint: [project-path ...]
disable-model-invocation: true
allowed-tools: Bash(super-agents *)
---

1. Run `super-agents setup $ARGUMENTS` (no arguments = the current project). It is idempotent, skips anything that is not a git repo, and prints what it wrote. If the current path is not a git repository, say that super-agents needs git for branches, review diffs and rollback, and offer to run `git init` (ask first; no remote is needed), then run setup again.
2. For the current project only, tailor `review.md` if it still contains `TODO` (a file with none was already tailored; leave it): first decide what the project holds (code, documents, data, a mixture) from what is in it, reading the README, package or build manifest, test config and CLAUDE.md. Fill only the lines that match. Replace the `TODO` lines. Put the real run/test/start-with-temp-data commands under "How to test this project", and add the failures that matter in this domain (money, personal data, migrations, external APIs) under "What counts as a failure". Only write commands you have confirmed exist. Set `Pre-merge checks` to `none` when there is nothing to run. If you cannot tell something, leave a short `TODO` and say so.
3. Report what changed, in one short list. For several paths, say which still have the generic `review.md`.
