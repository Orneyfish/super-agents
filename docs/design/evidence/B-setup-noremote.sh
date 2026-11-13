#!/usr/bin/env bash
# A second probe repo with NO remote: main at B, integration/x at C (checked out), probe/prev at D. Same logging hooks.
set -eu
S=${1:?scratchpad dir}; E=$S/evidence; W=$S/work; rm -rf "$W/probe-repo2"; mkdir -p "$W/probe-repo2"; cd "$W/probe-repo2"
git init -q -b main .; git config user.email t@t; git config user.name t
printf 'print("hello")\n' > app.py; git add -A; git commit -qm "A: base"
echo "# main" > LOCAL_MAIN.txt; git add -A; git commit -qm "B: main"
git switch -q -c integration/x; echo "# integration only" > INTEGRATION.txt; git add -A; git commit -qm "C: integration branch (checked out)"
git switch -q -c probe/prev; echo "# previous attempt" > PREV.txt; git add -A; git commit -qm "D: previous attempt, one ahead of C"; git switch -q integration/x
mkdir -p .claude; printf '.claude/\n' >> .git/info/exclude; cp "$W/probe-repo/.claude/settings.json" .claude/settings.json
git log --oneline --all --graph --decorate | cat; echo "remotes: $(git remote | wc -l)"
