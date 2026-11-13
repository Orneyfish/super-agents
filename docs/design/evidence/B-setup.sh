#!/usr/bin/env bash
# Part B setup: the probe repository and its project-level logging hooks. Everything lives under the scratchpad.
# Layout of the repo: a local bare "origin" at commit A; local main at B (ahead); integration/test at C (checked out);
# probe/prev at D (one ahead of C, a stand-in for a previous worker attempt). No push is used and nothing leaves the machine.
set -eu
S=${1:?scratchpad dir}; E=$S/evidence; W=$S/work; mkdir -p "$E/hooks"
gc() { git -c user.email=t@t -c user.name=t "$@"; }
rm -rf "$W/seed" "$W/probe-origin.git" "$W/probe-repo"
mkdir -p "$W/seed"; cd "$W/seed"; git init -q -b main .
printf 'print("hello")\n' > app.py
printf '{"cells":[{"cell_type":"code","execution_count":null,"metadata":{},"outputs":[],"source":["print(1)"]}],"metadata":{},"nbformat":4,"nbformat_minor":5}\n' > nb.ipynb
gc add -A; gc commit -qm "A: base (this is origin/main)"
cd "$W"; git clone -q --bare seed probe-origin.git; git clone -q probe-origin.git probe-repo; rm -rf seed
cd probe-repo; git config user.email t@t; git config user.name t
echo "# local main only" > LOCAL_MAIN.txt; git add -A; git commit -qm "B: local main, ahead of origin/main"
git switch -q -c integration/test; echo "# integration only" > INTEGRATION.txt; git add -A; git commit -qm "C: integration branch (checked out)"
git switch -q -c probe/prev; echo "# previous attempt" > PREV.txt; git add -A; git commit -qm "D: previous attempt, one ahead of C"; git switch -q integration/test
mkdir -p .claude; printf '.claude/\n' >> .git/info/exclude
python3 - "$E/hooks/probe-log.sh" "$E/hooks/probe-deny.sh" "$W/plugin-probe/scripts/sa-native.sh" > .claude/settings.json <<'PY'
import json, sys
log, deny, sa = sys.argv[1:4]
events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]
hooks = {e: [{"hooks": [{"type": "command", "command": f'"{log}" {e}'}]}] for e in events}
hooks["PreToolUse"].append({"matcher": "Write", "hooks": [{"type": "command", "command": f'"{deny}" "{sa}"'}]})
print(json.dumps({"hooks": hooks}, indent=1))
PY
git log --oneline --all --graph --decorate | cat
echo "status: $(git status --short | wc -l) changed files"; git remote -v; git symbolic-ref refs/remotes/origin/HEAD
