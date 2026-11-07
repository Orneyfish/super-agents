#!/usr/bin/env bash
# commit-tickets [-y] [-q]: commit the tickets and project files that workers need. Workers get worktrees of committed files only, so a
# ticket written or approved after 'superagent' started is missing from new worktrees until this runs. Lists what it will commit and
# asks first (-y skips the question; -q says nothing when there is nothing to commit). Only these paths are committed; anything else the user staged stays out.
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "commit-tickets: not inside a git repo" >&2; exit 1; }
cd "$top" || exit 1
yes=0 quiet=0; for o in "$@"; do case $o in -y) yes=1;; -q) quiet=1;; *) echo "usage: commit-tickets [-y] [-q]" >&2; exit 2;; esac; done
b=$(git branch --show-current)
case "$b" in main|master|trunk|"") echo "commit-tickets: on '${b:-detached HEAD}'; tickets are committed on the integration branch 'superagent' starts, not here" >&2; exit 1;; esac

paths=(); for x in specs/tickets .gitignore review.md CLAUDE.md AGENTS.md; do [ -e "$x" ] && paths+=("$x"); done
changed=""; [ ${#paths[@]} -gt 0 ] && changed=$(git status --short -- "${paths[@]}")
[ -n "$changed" ] || { ((quiet)) || echo "nothing to commit: the tickets and project files are already committed"; exit 0; }

echo "Tickets or project files are uncommitted, and workers only see committed files:"
echo "$changed"
if ((!yes)); then
  read -r -p "Commit them to '$b'? [Y/n] " a
  [[ ${a:-y} =~ ^[Yy] ]] || { echo "commit-tickets: refusing; workers would not see these changes" >&2; exit 1; }
fi
git add -A -- "${paths[@]}" && git commit -qm "super-agents: tickets and project files for the router" -- "${paths[@]}" || exit 1   # paths: the user's other staged work stays out
echo "done: committed to '$b'"
