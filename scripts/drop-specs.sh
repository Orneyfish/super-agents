#!/usr/bin/env bash
# drop-specs: run on the integration branch (the one the PR comes from, not a worker branch) once every ticket is done. Commits the
# removal of everything tracked under specs/ (tickets, BOARD.md, specs committed before 'setup'), so the requirements and eval
# documents do not land in the project. They stay in this branch's history: git show <sha>:specs/...
# Single-feature specs are git-ignored by 'setup', so a project set up from the start has nothing else to drop.
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "drop-specs: not inside a git repo" >&2; exit 1; }
cd "$top" || exit 1
[ $# -eq 0 ] || { echo "usage: drop-specs" >&2; exit 2; }
b=$(git branch --show-current)
case "$b" in main|master|trunk|"") echo "drop-specs: on '${b:-detached HEAD}'; run it on the branch you are about to merge, not here" >&2; exit 1;; esac
# what HEAD carries, not the index: a removal that is staged but whose commit failed must still be committed when this is re-run
[ -n "$(git ls-tree -r --name-only HEAD specs)" ] || { echo "nothing to drop: this branch carries no specs/ files"; exit 0; }

# every ticket folder on this branch must be done on this branch's board; a missing or unreadable board fails closed
board=$(git show HEAD:specs/tickets/BOARD.md 2>/dev/null)
open=""
while read -r n; do
  grep -Eq "^\| *$n *\|[^|]*\| *done *\|" <<<"$board" || open+="  $n"$'\n'
done < <(git ls-tree -r --name-only HEAD specs/tickets | sed -n 's#^specs/tickets/\([0-9][0-9][0-9]\)-.*#\1#p' | sort -u)
[ -z "$open" ] || { printf 'drop-specs: these tickets are not marked done on the committed specs/tickets/BOARD.md:\n%s' "$open" >&2; exit 1; }

# git rm refuses files with uncommitted edits, which is what we want: they would be lost for good
git rm -r -q --ignore-unmatch specs || { echo "drop-specs: specs/ has uncommitted changes; run 'super-agents commit-tickets' first" >&2; exit 1; }
git commit -qm "super-agents: drop specs before merge" -- specs || exit 1   # paths: the user's other staged work stays out
echo "done: dropped specs/ from '$b' (still in its history)"
