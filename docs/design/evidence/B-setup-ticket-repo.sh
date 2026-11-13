#!/usr/bin/env bash
# A repo with one approved, committed ticket and no results: the real worker gate must refuse a worker that stops here.
set -eu
S=${1:?scratchpad dir}; E=$S/evidence; W=$S/work; P=$W/plugin-stubworker; D=$W/probe-repo3
rm -rf "$D"; mkdir -p "$D/specs/tickets/001-add"; cd "$D"; git init -q -b main .; git config user.email t@t; git config user.name t
echo 'print("hi")' > app.py; git add -A; git commit -qm base; git switch -q -c integration/y
"$P/bin/super-agents" setup . >/dev/null
printf '# Add\n\n**Status:** draft\n**Risk:** low\n\n## Functional requirements\n- FR-1: `python3 app.py add 1 2` prints 3.\n\nUI: no\n' > specs/tickets/001-add/RD.md
printf '# Evals: Add\n\n## Setup\n1. none\n\n## E1: add\n- covers: FR-1\n- check: `python3 app.py add 1 2`\n- pass when: prints 3\n- fail when: prints anything else\n' > specs/tickets/001-add/evals.md
printf '# Board\n| # | Title | Status | Mode | Runs |\n|---|-------|--------|------|------|\n| 001 | Add | draft | solo | alongside |\n' > specs/tickets/BOARD.md
"$P/bin/super-agents" check-evals specs/tickets/001-add; "$P/bin/super-agents" board set 001 ready; "$P/bin/super-agents" board check
mkdir -p .claude; printf '.claude/settings.json\n' >> .git/info/exclude; cp "$W/demo/.claude/settings.json" .claude/settings.json
git add -A; git commit -qm "ticket 001 approved"; git status --short | wc -l; git log --oneline | cat
