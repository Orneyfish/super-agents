#!/usr/bin/env bash
# SubagentStop hook: a ticket worker may not finish until every eval passes in results.md (or it declared itself blocked, or waits for the user's answer).
# Escape hatches: no job file, a blocked or waiting phase, and a 3-block cap, so it can never wedge a worker. A gate that cannot run says so.
here="$(cd "$(dirname "$0")" && pwd)"; get() { "$here/sa-native.sh" hookio get "$@"; }; emit() { "$here/sa-native.sh" hookio emit "$@"; }
in=$(cat)
grep -q worker <<<"$in" || exit 0                                       # cheap pre-filter
"$here/sa-native.sh" --version >/dev/null 2>&1 || { echo '{"systemMessage": "super-agents: worker gate skipped (sa-core is not available here; run super-agents install-core); nothing checked that its evals pass."}'; exit 0; }
skip() { emit message "super-agents: worker gate skipped ($1); nothing checked that its evals pass."; exit 0; }
at=$(get agent_type <<<"$in") || skip "hook input unreadable"
[ "$at" = super-agents:worker ] || exit 0
cwd=$(get cwd <<<"$in"); st="$cwd/.job/status.json"; [ -f "$st" ] || skip "no $st"
# a job file the repository ships (git-tracked) or a symlink is not this worker's heartbeat
if [ -L "$st" ] || [ -L "$cwd/.job" ] || git -C "$cwd" ls-files --error-unmatch -- "$st" >/dev/null 2>&1; then skip ".job/status.json is tracked by git or a symlink"; fi
# The ticket folder is the one in this worktree, found by ticket number. 'dir' in the status file is the worker's own text and
# could name any folder that happens to pass, so it is not read.
n=$(get ticket <"$st"); [[ $n =~ ^[0-9]{3}$ ]] || skip "no ticket number in $st"
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || skip "$cwd is not inside a git repository"
set -- "$top"/specs/tickets/"$n"-*/; { [ $# = 1 ] && [ -d "$1" ]; } || skip "no single ticket folder specs/tickets/$n-* in $top"
dir=${1%/}
case "$(get phase <"$st")" in blocked|waiting) exit 0;; esac   # waiting: it stopped to ask the user; before the counter, so the wait spends no block
out=$("$(dirname "$0")/check-evals.sh" "$dir" --passed) && exit 0
n=$(cat "$cwd/.job/gate_blocks" 2>/dev/null); [[ $n =~ ^[0-9]{1,3}$ ]] && n=$((10#$n)) || n=0   # never arithmetic on text from the file; garbage counts as 0, so the gate blocks
[ "$n" -ge 3 ] && { emit message "super-agents: worker gate released after 3 blocks; evals still unmet."; exit 0; }
echo $((n+1)) > "$cwd/.job/gate_blocks"
emit block "Not done yet:
$out
Fix and re-test, then update results.md. If you truly cannot, run 'super-agents job-status blocked \"<why>\"' and say so in your report."
