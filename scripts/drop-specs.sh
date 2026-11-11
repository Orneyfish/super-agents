#!/usr/bin/env bash
# drop-specs: run on the branch you are about to merge. Commits the removal of the tracked specs/ files (tickets, BOARD.md), so the
# requirements and eval documents do not land in the project. They stay in this branch's history: git show <sha>:specs/...
# Single-feature specs are git-ignored by 'setup' and never tracked, so there is nothing to drop for them.
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "drop-specs: not inside a git repo" >&2; exit 1; }
cd "$top" || exit 1
[ $# -eq 0 ] || { echo "usage: drop-specs" >&2; exit 2; }
b=$(git branch --show-current)
case "$b" in main|master|trunk|"") echo "drop-specs: on '${b:-detached HEAD}'; run it on the branch you are about to merge, not here" >&2; exit 1;; esac
[ -n "$(git ls-files specs)" ] || { echo "nothing to drop: no specs/ files are tracked"; exit 0; }

# dropping the board while a ticket is still being built would take it away from the workers
open=$(awk -F'|' '$2 ~ /^ *[0-9][0-9][0-9] *$/ && $4 !~ /^ *done *$/ {printf "  %s%s\n", $2, $4}' specs/tickets/BOARD.md 2>/dev/null)
[ -z "$open" ] || { printf 'drop-specs: these tickets are not done yet:\n%s\n' "$open" >&2; exit 1; }

# git rm refuses files with uncommitted edits, which is what we want: they would be lost for good
git rm -r -q specs || { echo "drop-specs: specs/ has uncommitted changes; run 'super-agents commit-tickets' first" >&2; exit 1; }
git commit -qm "super-agents: drop specs before merge" -- specs || exit 1   # paths: the user's other staged work stays out
echo "done: dropped specs/ from '$b' (still in its history)"
